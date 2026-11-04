using System.Collections.Concurrent;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

/// <summary>Blockwechsel: ein „upcoming“-Plan wird an seinem Starttag aktiv, der bisherige archiviert.</summary>
public static class PlanLifecycle
{
    public static async Task PromoteAsync(MongoContext db, string userId, DateOnly today, CancellationToken ct)
    {
        var next = await db.Plans.Find(p => p.UserId == userId && p.Status == "upcoming").FirstOrDefaultAsync(ct);
        if (next is null || DateOnly.ParseExact(next.StartDate, "yyyy-MM-dd") > today) return;

        await db.Plans.UpdateManyAsync(p => p.UserId == userId && p.Status == "active",
            Builders<PlanDoc>.Update.Set(p => p.Status, "archived"), cancellationToken: ct);
        await db.Plans.UpdateOneAsync(p => p.Id == next.Id,
            Builders<PlanDoc>.Update.Set(p => p.Status, "active"), cancellationToken: ct);
    }
}

/// <summary>
/// Läuft im Hintergrund: aktiviert Folgeblöcke an ihrem Starttag und erstellt 3 Tage vor Ende des aktiven Blocks
/// automatisch den nächsten (Art „adapted“, also auf Basis der Ergebnisse des laufenden Blocks).
/// </summary>
public sealed class AutoBlockService : BackgroundService
{
    private const int DaysBeforeEnd = 3;
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan RetryAfterFailure = TimeSpan.FromHours(12); // fehlgeschlagene KI-Aufrufe nicht ständig wiederholen

    private readonly IServiceScopeFactory _scopes;
    private readonly AppOptions _options;
    private readonly ILogger<AutoBlockService> _log;
    private readonly ConcurrentDictionary<string, DateTime> _lastFailure = new();

    public AutoBlockService(IServiceScopeFactory scopes, AppOptions options, ILogger<AutoBlockService> log)
    {
        _scopes = scopes;
        _options = options;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); // MongoDB-Start abwarten
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _log.LogError(ex, "Automatischer Blockwechsel fehlgeschlagen");
            }
            await Task.Delay(Interval, stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<MongoContext>();
        var plans = scope.ServiceProvider.GetRequiredService<PlanService>();
        var today = BlockPlanner.Today(_options.TimeZone);

        var users = await db.Users.Find(_ => true).ToListAsync(ct);
        foreach (var user in users)
        {
            await PlanLifecycle.PromoteAsync(db, user.Id, today, ct);

            var active = await db.Plans.Find(p => p.UserId == user.Id && p.Status == "active")
                .SortByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct);
            if (active is null) continue;
            var end = DateOnly.ParseExact(active.StartDate, "yyyy-MM-dd").AddDays(active.Weeks * 7 - 1);
            if (end.DayNumber - today.DayNumber > DaysBeforeEnd) continue;
            if (await db.Plans.CountDocumentsAsync(p => p.UserId == user.Id && p.Status == "upcoming", cancellationToken: ct) > 0)
                continue;
            if (_lastFailure.TryGetValue(user.Id, out var failedAt) && DateTime.UtcNow - failedAt < RetryAfterFailure)
                continue;

            try
            {
                _log.LogInformation("Erstelle Folgeblock für {User} (aktiver Block endet {End})", user.Name, end);
                var doc = await plans.CreateAsync(user, "adapted", null, null, null, ct);
                _log.LogInformation("Folgeblock für {User}: Start {Start}, {Weeks} Wochen, Status {Status}",
                    user.Name, doc.StartDate, doc.Weeks, doc.Status);
                _lastFailure.TryRemove(user.Id, out _);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _lastFailure[user.Id] = DateTime.UtcNow;
                _log.LogWarning("Folgeblock für {User} fehlgeschlagen: {Message}", user.Name, ex.Message);
            }
        }
    }
}
