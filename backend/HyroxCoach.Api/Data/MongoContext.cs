using HyroxCoach.Api.Config;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Data;

public sealed class MongoContext
{
    public IMongoCollection<User> Users { get; }
    public IMongoCollection<Anamnese> Anamneses { get; }
    public IMongoCollection<HyroxResult> Results { get; }
    public IMongoCollection<PlanDoc> Plans { get; }
    public IMongoCollection<WorkoutLog> Workouts { get; }
    public IMongoCollection<AiUsage> Usage { get; }
    public IMongoCollection<PlanChat> Chats { get; }

    public MongoContext(AppOptions options)
    {
        var client = new MongoClient(options.MongoConnection);
        var db = client.GetDatabase(options.MongoDb);
        Users = db.GetCollection<User>("users");
        Anamneses = db.GetCollection<Anamnese>("anamneses");
        Results = db.GetCollection<HyroxResult>("results");
        Plans = db.GetCollection<PlanDoc>("plans");
        Workouts = db.GetCollection<WorkoutLog>("workouts");
        Usage = db.GetCollection<AiUsage>("ai_usage");
        Chats = db.GetCollection<PlanChat>("plan_chats");
    }

    /// <summary>Legt Indizes an. Versucht es mehrfach, weil MongoDB beim Container-Start evtl. noch nicht bereit ist.</summary>
    public async Task EnsureIndexesAsync(ILogger logger, CancellationToken ct = default)
    {
        for (var attempt = 1; attempt <= 15; attempt++)
        {
            try
            {
                await Users.Indexes.CreateOneAsync(
                    new CreateIndexModel<User>(Builders<User>.IndexKeys.Ascending(u => u.NameKey),
                        new CreateIndexOptions { Unique = true }), cancellationToken: ct);
                await Users.Indexes.CreateOneAsync(
                    new CreateIndexModel<User>(Builders<User>.IndexKeys.Ascending(u => u.TokenHash),
                        new CreateIndexOptions { Unique = true }), cancellationToken: ct);
                await Results.Indexes.CreateOneAsync(
                    new CreateIndexModel<HyroxResult>(Builders<HyroxResult>.IndexKeys.Ascending(r => r.UserId)), cancellationToken: ct);
                await Plans.Indexes.CreateOneAsync(
                    new CreateIndexModel<PlanDoc>(Builders<PlanDoc>.IndexKeys.Ascending(p => p.UserId).Descending(p => p.CreatedAt)), cancellationToken: ct);
                await Workouts.Indexes.CreateOneAsync(
                    new CreateIndexModel<WorkoutLog>(Builders<WorkoutLog>.IndexKeys.Ascending(w => w.UserId).Ascending(w => w.Date)), cancellationToken: ct);
                await Usage.Indexes.CreateOneAsync(
                    new CreateIndexModel<AiUsage>(Builders<AiUsage>.IndexKeys.Ascending(u => u.UserId).Descending(u => u.At)), cancellationToken: ct);
                logger.LogInformation("MongoDB bereit, Indizes angelegt.");
                return;
            }
            catch (Exception ex) when (attempt < 15)
            {
                logger.LogWarning("MongoDB noch nicht erreichbar (Versuch {Attempt}/15): {Message}", attempt, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(2), ct);
            }
        }
    }
}
