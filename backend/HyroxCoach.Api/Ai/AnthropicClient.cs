using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Ai;

public sealed record AiResult(JsonElement ToolInput, int InputTokens, int OutputTokens, string StopReason);

/// <summary>Antwort eines freien Aufrufs: Text und optional ein Tool-Aufruf.</summary>
public sealed record AiReply(string Text, string? ToolName, JsonElement? ToolInput, int InputTokens, int OutputTokens, string StopReason);

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
        var messages = new JsonArray(new JsonObject
        {
            ["role"] = "user",
            ["content"] = userMessage
        });
        var tools = new JsonArray(new JsonObject
        {
            ["name"] = toolName,
            ["description"] = toolDescription,
            ["input_schema"] = inputSchema.DeepClone()
        });

        var reply = await CallAsync(system, messages, tools, maxTokens, ct);
        if (reply.ToolName == toolName && reply.ToolInput is { } input)
            return new AiResult(input, reply.InputTokens, reply.OutputTokens, reply.StopReason);

        // Abgeschnitten, bevor der Tool-Aufruf fertig war: PlanService erkennt das am StopReason und versucht es erneut.
        if (reply.StopReason == "max_tokens")
            return new AiResult(default, reply.InputTokens, reply.OutputTokens, reply.StopReason);

        throw new ApiException(502, "Die KI-Antwort enthielt keinen Plan (kein Tool-Aufruf).");
    }

    /// <summary>Freier Aufruf mit Verlauf. Das Modell darf antworten oder eines der Tools aufrufen.</summary>
    public async Task<AiReply> CallAsync(
        string system,
        JsonArray messages,
        JsonArray tools,
        int maxTokens,
        CancellationToken ct,
        string? effort = null)
    {
        if (string.IsNullOrWhiteSpace(_options.AnthropicApiKey))
            throw new ApiException(503, "ANTHROPIC_API_KEY ist im Backend nicht gesetzt.");

        var body = new JsonObject
        {
            ["model"] = _options.AnthropicModel,
            ["max_tokens"] = maxTokens,
            // Denkaufwand begrenzen: Thinking-Tokens zählen in max_tokens.
            ["output_config"] = new JsonObject
            {
                ["effort"] = effort ?? _options.PlanEffort
            },
            ["system"] = system,
            ["messages"] = messages
        };
        if (tools.Count > 0)
        {
            body["tools"] = tools;
            // Neuere Modelle (z. B. claude-sonnet-5-5) lehnen erzwungenes tool_choice ("tool"/"any") ab.
            // Der System-Prompt weist an, wann das Tool aufzurufen ist.
            body["tool_choice"] = new JsonObject { ["type"] = "auto" };
        }

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

        var replyText = new StringBuilder();
        string? toolName = null;
        JsonElement? toolInput = null;
        if (root.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in content.EnumerateArray())
            {
                var type = item.TryGetProperty("type", out var t) ? t.GetString() : null;
                if (type == "text" && item.TryGetProperty("text", out var tx))
                {
                    replyText.Append(tx.GetString());
                }
                else if (type == "tool_use" && toolName is null && item.TryGetProperty("input", out var input))
                {
                    toolName = item.TryGetProperty("name", out var n) ? n.GetString() : null;
                    toolInput = input.Clone();
                }
            }
        }

        return new AiReply(replyText.ToString().Trim(), toolName, toolInput, inputTokens, outputTokens, stopReason);
    }
}
