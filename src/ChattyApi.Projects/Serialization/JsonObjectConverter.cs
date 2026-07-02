using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Generic base class for the model converters. It factors out the boilerplate
/// (token checks, buffering the object into a <see cref="JsonElement"/>, writing the
/// object envelope) so each concrete converter only expresses its own mapping and
/// validation rules.
/// </summary>
/// <typeparam name="T">The model type handled by the converter.</typeparam>
public abstract class JsonObjectConverter<T> : JsonConverter<T>
    where T : class
{
    /// <summary>A short human-readable name for <typeparamref name="T"/>, used in error messages.</summary>
    protected abstract string Subject { get; }

    public sealed override T Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.StartObject)
        {
            throw new JsonException($"{Subject}: expected a JSON object but found '{reader.TokenType}'.");
        }

        using JsonDocument document = JsonDocument.ParseValue(ref reader);
        return ReadCore(document.RootElement, options);
    }

    public sealed override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        WriteCore(writer, value, options);
        writer.WriteEndObject();
    }

    /// <summary>Materializes and validates the model from a buffered JSON object.</summary>
    protected abstract T ReadCore(JsonElement element, JsonSerializerOptions options);

    /// <summary>Writes the model's properties (the object envelope is already handled).</summary>
    protected abstract void WriteCore(Utf8JsonWriter writer, T value, JsonSerializerOptions options);

    /// <summary>
    /// Runs a model constructor/factory and converts its <see cref="ProjectValidationException"/>
    /// into a <see cref="JsonException"/> carrying the given context, so deserialization errors
    /// always surface as JSON errors with a precise location description.
    /// </summary>
    protected static TResult Materialize<TResult>(string context, Func<TResult> factory)
    {
        try
        {
            return factory();
        }
        catch (ProjectValidationException ex)
        {
            throw new JsonException($"{context}: {ex.Message}", ex);
        }
    }
}
