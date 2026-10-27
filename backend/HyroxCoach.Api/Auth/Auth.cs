using System.Security.Cryptography;
using System.Text;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Auth;

public static class AuthHelper
{
    public static string NewCode() => Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();

    public static string Hash(string code)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(code));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static string NameKey(string name) => name.Trim().ToLowerInvariant();

    public static bool ConstantTimeEquals(string a, string b)
    {
        var x = Encoding.UTF8.GetBytes(a);
        var y = Encoding.UTF8.GetBytes(b);
        return CryptographicOperations.FixedTimeEquals(x, y);
    }

    public static bool IsAdmin(HttpContext ctx, AppOptions options)
    {
        if (string.IsNullOrEmpty(options.AdminKey)) return false;
        var header = ctx.Request.Headers["X-Admin-Key"].ToString();
        return header.Length > 0 && ConstantTimeEquals(header, options.AdminKey);
    }

    public static User CurrentUser(this HttpContext ctx) => (User)ctx.Items["user"]!;
}

/// <summary>Prüft bei allen /api/*-Aufrufen den Einladungscode (Bearer) und setzt den Nutzer.</summary>
public sealed class TokenAuthMiddleware
{
    private readonly RequestDelegate _next;

    public TokenAuthMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext ctx, MongoContext db)
    {
        var header = ctx.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            await Reject(ctx);
            return;
        }

        var code = header["Bearer ".Length..].Trim();
        var hash = AuthHelper.Hash(code);
        var user = await db.Users.Find(u => u.TokenHash == hash).FirstOrDefaultAsync(ctx.RequestAborted);
        if (user is null)
        {
            await Reject(ctx);
            return;
        }

        ctx.Items["user"] = user;
        await _next(ctx);
    }

    private static async Task Reject(HttpContext ctx)
    {
        ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await ctx.Response.WriteAsJsonAsync(new { error = "Nicht angemeldet." });
    }
}
