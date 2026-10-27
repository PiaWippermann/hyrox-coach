using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using HyroxCoach.Api.Ai;
using HyroxCoach.Api.Auth;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using HyroxCoach.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);

var options = AppOptions.FromEnvironment();
builder.Services.AddSingleton(options);
builder.Services.AddSingleton<MongoContext>();
builder.Services.AddScoped<PlanService>();
builder.Services.AddHttpClient<AnthropicClient>(client =>
{
    client.BaseAddress = new Uri(options.AnthropicBaseUrl);
    client.Timeout = TimeSpan.FromMinutes(8); // lange Pläne brauchen bei großen Ausgaben mehrere Minuten
});

builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
    o.SerializerOptions.Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping;
});

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("login", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
});

var app = builder.Build();

// Fehler mit Status (ApiException) als JSON zurückgeben
app.Use(async (ctx, next) =>
{
    try
    {
        await next();
    }
    catch (ApiException ex)
    {
        ctx.Response.StatusCode = ex.Status;
        await ctx.Response.WriteAsJsonAsync(new { error = ex.Message });
    }
});

app.UseRateLimiter();
app.UseWhen(ctx => ctx.Request.Path.StartsWithSegments("/api"),
    branch => branch.UseMiddleware<TokenAuthMiddleware>());

await app.Services.GetRequiredService<MongoContext>().EnsureIndexesAsync(app.Logger);

// ---------- offen ----------
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapPost("/auth/login", async (LoginRequest req, MongoContext db) =>
{
    var key = AuthHelper.NameKey(req.Name ?? "");
    var user = await db.Users.Find(u => u.NameKey == key).FirstOrDefaultAsync();
    var ok = user is not null && AuthHelper.ConstantTimeEquals(user.TokenHash, AuthHelper.Hash(req.Code ?? ""));
    if (!ok) return Results.Json(new { error = "Name oder Code stimmt nicht." }, statusCode: 401);

    var uid = user!.Id;
    var hasAnamnese = await db.Anamneses.CountDocumentsAsync(a => a.UserId == uid) > 0;
    var hasPlan = await db.Plans.CountDocumentsAsync(p => p.UserId == uid && p.Status == "active") > 0;
    return Results.Ok(new { userId = uid, name = user.Name, hasAnamnese, hasPlan });
}).RequireRateLimiting("login");

// ---------- Admin ----------
app.MapPost("/admin/users", async (CreateUserRequest req, HttpContext ctx, MongoContext db, AppOptions opt) =>
{
    if (!AuthHelper.IsAdmin(ctx, opt)) return Results.Json(new { error = "Nicht erlaubt." }, statusCode: 401);

    var name = (req.Name ?? "").Trim();
    if (name.Length < 2 || name.Length > 40) throw new ApiException(400, "Name muss 2 bis 40 Zeichen lang sein.");

    var key = AuthHelper.NameKey(name);
    if (await db.Users.CountDocumentsAsync(u => u.NameKey == key) > 0)
        throw new ApiException(409, "Dieser Name ist schon vergeben.");

    var code = AuthHelper.NewCode();
    var user = new User { Name = name, NameKey = key, TokenHash = AuthHelper.Hash(code) };
    await db.Users.InsertOneAsync(user);
    return Results.Ok(new { userId = user.Id, name = user.Name, code });
});

// ---------- API (Bearer) ----------
var api = app.MapGroup("/api");

api.MapGet("/anamnese", async (HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var a = await db.Anamneses.Find(x => x.UserId == u.Id).FirstOrDefaultAsync();
    return a is null ? Results.NotFound(new { error = "Noch keine Anamnese." }) : Results.Ok(a);
});

api.MapPut("/anamnese", async (Anamnese body, HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    body.UserId = u.Id;
    body.UpdatedAt = DateTime.UtcNow;
    await db.Anamneses.ReplaceOneAsync(x => x.UserId == u.Id, body, new ReplaceOptions { IsUpsert = true });
    return Results.Ok(body);
});

api.MapGet("/anamnese/suggestions", async (HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var a = await db.Anamneses.Find(x => x.UserId == u.Id).FirstOrDefaultAsync();
    if (a is null) throw new ApiException(400, "Bitte zuerst die Anamnese speichern.");
    var latest = await db.Results.Find(r => r.UserId == u.Id).SortByDescending(r => r.Date).FirstOrDefaultAsync();
    return Results.Ok(FocusSuggester.Suggest(a, latest));
});

api.MapGet("/results", async (HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var list = await db.Results.Find(r => r.UserId == u.Id).SortByDescending(r => r.Date).ToListAsync();
    return Results.Ok(list);
});

api.MapPost("/results", async (HyroxResult body, HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    if (body.RunsSec.Count != 8 || body.StationsSec.Count != 8)
        throw new ApiException(400, "Es werden genau 8 Lauf- und 8 Stationszeiten erwartet (in Sekunden).");
    if (!DateOnly.TryParseExact(body.Date, "yyyy-MM-dd", out _))
        throw new ApiException(400, "date muss das Format yyyy-MM-dd haben.");

    body.Id = Guid.NewGuid().ToString("N");
    body.UserId = u.Id;
    body.Source = "manual";
    if (body.TotalTimeSec <= 0)
        body.TotalTimeSec = body.RunsSec.Sum() + body.StationsSec.Sum() + (body.RoxzoneSec ?? 0);
    await db.Results.InsertOneAsync(body);
    return Results.Ok(body);
});

api.MapDelete("/results/{id}", async (string id, HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var res = await db.Results.DeleteOneAsync(r => r.Id == id && r.UserId == u.Id);
    return res.DeletedCount > 0 ? Results.NoContent() : Results.NotFound();
});

static object PlanEnvelope(PlanDoc p)
{
    using var doc = JsonDocument.Parse(p.PlanJson);
    return new
    {
        id = p.Id,
        createdAt = p.CreatedAt,
        startDate = p.StartDate,
        weeks = p.Weeks,
        kind = p.Kind,
        status = p.Status,
        plan = doc.RootElement.Clone()
    };
}

api.MapGet("/plans/current", async (HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var p = await db.Plans.Find(x => x.UserId == u.Id && x.Status == "active")
        .SortByDescending(x => x.CreatedAt).FirstOrDefaultAsync();
    return p is null ? Results.NotFound(new { error = "Noch kein Plan." }) : Results.Ok(PlanEnvelope(p));
});

api.MapPost("/plans/generate", async (GeneratePlanRequest req, HttpContext ctx, PlanService plans) =>
{
    var doc = await plans.CreateAsync(ctx.CurrentUser(), "initial", req.StartDate, req.Weeks, null, ctx.RequestAborted);
    return Results.Ok(PlanEnvelope(doc));
});

api.MapPost("/plans/adapt", async (AdaptPlanRequest req, HttpContext ctx, PlanService plans) =>
{
    var doc = await plans.CreateAsync(ctx.CurrentUser(), "adapted", req.StartDate, req.Weeks, req.Notes, ctx.RequestAborted);
    return Results.Ok(PlanEnvelope(doc));
});

api.MapPost("/workouts", async (WorkoutLog body, HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    if (!DateOnly.TryParseExact(body.Date, "yyyy-MM-dd", out _))
        throw new ApiException(400, "date muss das Format yyyy-MM-dd haben.");
    if (body.Location != "gym" && body.Location != "home")
        throw new ApiException(400, "location muss gym oder home sein.");
    if (body.Rpe is < 1 or > 10)
        throw new ApiException(400, "rpe muss zwischen 1 und 10 liegen.");

    body.Id = Guid.NewGuid().ToString("N");
    body.UserId = u.Id;
    if (body.DurationMin is null && body.StartedAt.HasValue && body.FinishedAt.HasValue)
        body.DurationMin = (int)Math.Round((body.FinishedAt.Value - body.StartedAt.Value).TotalMinutes);
    await db.Workouts.InsertOneAsync(body);
    return Results.Ok(body);
});

api.MapGet("/workouts", async (
    [FromQuery(Name = "from")] string? fromDate,
    [FromQuery(Name = "to")] string? toDate,
    HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var f = Builders<WorkoutLog>.Filter;
    var filter = f.Eq(w => w.UserId, u.Id);
    if (!string.IsNullOrEmpty(fromDate)) filter &= f.Gte(w => w.Date, fromDate);
    if (!string.IsNullOrEmpty(toDate)) filter &= f.Lte(w => w.Date, toDate);
    var list = await db.Workouts.Find(filter).SortByDescending(w => w.Date).ToListAsync();
    return Results.Ok(list);
});

api.MapGet("/progress", async (HttpContext ctx, MongoContext db) =>
{
    var u = ctx.CurrentUser();
    var logs = await db.Workouts.Find(w => w.UserId == u.Id).ToListAsync();
    return Results.Ok(ProgressService.Build(logs));
});

api.MapGet("/usage", async (HttpContext ctx, MongoContext db, AppOptions opt) =>
{
    var u = ctx.CurrentUser();
    var now = DateTime.UtcNow;
    var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
    var rows = await db.Usage.Find(x => x.UserId == u.Id && x.At >= monthStart).ToListAsync();
    return Results.Ok(new
    {
        callsThisMonth = rows.Count,
        monthlyLimit = opt.AiMaxCallsPerMonth,
        dailyLimit = opt.AiMaxCallsPerDay,
        inputTokens = rows.Sum(r => (long)r.InputTokens),
        outputTokens = rows.Sum(r => (long)r.OutputTokens),
        model = opt.AnthropicModel
    });
});

app.Run();
