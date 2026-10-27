namespace HyroxCoach.Api.Config;

/// <summary>Konfiguration ausschließlich über Umgebungsvariablen (siehe .env.example).</summary>
public sealed class AppOptions
{
    public string MongoConnection { get; init; } = "mongodb://localhost:27017";
    public string MongoDb { get; init; } = "hyroxcoach";
    public string AdminKey { get; init; } = "";
    public string AnthropicApiKey { get; init; } = "";
    public string AnthropicModel { get; init; } = "claude-sonnet-5-5";
    public string AnthropicBaseUrl { get; init; } = "https://api.anthropic.com";
    public int AiMaxCallsPerDay { get; init; } = 4;
    public int AiMaxCallsPerMonth { get; init; } = 8;
    public int PlanMaxTokens { get; init; } = 16000;

    public static AppOptions FromEnvironment()
    {
        static string Get(string key, string fallback)
        {
            var v = Environment.GetEnvironmentVariable(key);
            return string.IsNullOrWhiteSpace(v) ? fallback : v;
        }

        static int GetInt(string key, int fallback)
        {
            return int.TryParse(Environment.GetEnvironmentVariable(key), out var v) ? v : fallback;
        }

        return new AppOptions
        {
            MongoConnection = Get("MONGO_CONNECTION", "mongodb://localhost:27017"),
            MongoDb = Get("MONGO_DB", "hyroxcoach"),
            AdminKey = Get("ADMIN_KEY", ""),
            AnthropicApiKey = Get("ANTHROPIC_API_KEY", ""),
            AnthropicModel = Get("ANTHROPIC_MODEL", "claude-sonnet-5-5"),
            AnthropicBaseUrl = Get("ANTHROPIC_BASE_URL", "https://api.anthropic.com"),
            AiMaxCallsPerDay = GetInt("AI_MAX_CALLS_PER_DAY", 4),
            AiMaxCallsPerMonth = GetInt("AI_MAX_CALLS_PER_MONTH", 8),
            PlanMaxTokens = GetInt("PLAN_MAX_TOKENS", 16000),
        };
    }
}
