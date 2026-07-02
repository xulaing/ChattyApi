using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Serializes <see cref="FieldType"/> as its lowercase wire name ("string", "number", ...)
/// and rejects unknown names with a message listing the supported types.
/// </summary>
public sealed class FieldTypeJsonConverter : JsonConverter<FieldType>
{
    public override FieldType Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String)
        {
            throw new JsonException($"Expected a field type as a JSON string but found '{reader.TokenType}'.");
        }

        string wireName = reader.GetString()!;
        if (!FieldTypes.TryParse(wireName, out FieldType type))
        {
            throw new JsonException(
                $"'{wireName}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}.");
        }

        return type;
    }

    public override void Write(Utf8JsonWriter writer, FieldType value, JsonSerializerOptions options) =>
        writer.WriteStringValue(FieldTypes.GetWireName(value));
}
