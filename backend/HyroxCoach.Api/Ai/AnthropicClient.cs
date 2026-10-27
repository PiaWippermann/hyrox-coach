using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Ai;

public sealed record AiResult(JsonElement ToolInput, int InputTokens, int OutputTokens, string StopReason);

/// <summary>
/// Minimaler Client für die Claude Messages API (reines HTTP, ohne SDK).
/// Das Ergebnis wird über einen erzwungenen Tool-Aufruf geliefert, dessen input_schema unser Plan-Schema ist.
/// </summary>
public sealed class AnthropicClient
{
    private readonly HttpClient _http;
    private readonly AppOptions _options;

    public AnthropicClient(HttpClient http, AppOptions options)
    {
        _http = http;
        _options = options;
    }

    public async Task<AiResult> CallToolAsync(
        string system,
        string userMessage,
        string toolName,
        string toolDescription,
        JsonNode inputSchema,
        int maxTokens,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_options.AnthropicApiKey))
            throw new ApiException(503, "ANTHROPIC_API_KEY ist im Backend nicht gesetzt.");

        var body = new JsonObject
        {
            ["model"] = _options.AnthropicModel,
            ["max_tokens"] = maxTokens,
            ["system"] = system,
            ["messages"] = new JsonArray(new JsonObject
            {
                ["role"] = "user",
                ["content"] = userMessage
            }),
            ["tools"] = new JsonArray(new JsonObject
            {
                ["name"] = toolName,
                ["description"] = toolDescription,
                ["input_schema"] = inputSchema.DeepClone()
            }),
            ["tool_choice"] = new JsonObject
            {
                ["type"] = "tool",
                ["name"] = toolName
            }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/messages")
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json")
        };
        request.Headers.Add("x-api-key", _options.AnthropicApiKey);
        request.Headers.Add("anthropic-version", "2023-06-01");

        using var response = await _http.SendAsync(request, ct);
        var text = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
        {
            var shortText = text.Length > 400 ? text[..400] : text;
            throw new ApiException(502, $"Claude API Fehler {(int)response.StatusCode}: {shortText}");
        }

        using var doc = JsonDocument.Parse(text);
        var root = doc.RootElement;

        var stopReason = root.TryGetProperty("stop_reason", out var sr) ? sr.GetString() ?? "" : "";
        var inputTokens = 0;
        var outputTokens = 0;
        if (root.TryGetProperty("usage", out var usage))
        {
            if (usage.TryGetProperty("input_tokens", out var it)) inputTokens = it.GetInt32();
            if (usage.TryGetProperty("output_tokens", out var ot)) outputTokens = ot.GetInt32();
        }

        if (root.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in content.EnumerateArray())
            {
                var type = item.TryGetProperty("type", out var t) ? t.GetString() : null;
                var name = item.TryGetProperty("name", out var n) ? n.GetString() : null;
                if (type == "tool_use" && name == toolName && item.TryGetProperty("input", out var input))
                {
                    return new AiResult(input.Clone(), inputTokens, outputTokens, stopReason);
                }
            }
        }

        throw new ApiException(502, "Die KI-Antwort enthielt keinen Plan (kein Tool-Aufruf).");
    }
}
