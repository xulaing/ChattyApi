using System.Text.Json;
using ChattyApi.Projects.Values;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Wire format: <c>{ "name": "field1", "type": "number", "value": 12 }</c>.
/// The value is written with its native JSON type (raw number, raw boolean,
/// real JSON array for lists, ...) and strictly validated against the declared
/// type on read. A missing or null "value" property yields a null value.
/// </summary>
public sealed class ExampleFieldJsonConverter : JsonObjectConverter<ExampleField>
{
    protected override string Subject => "Example field";

    protected override ExampleField ReadCore(JsonElement element, JsonSerializerOptions options)
    {
        string name = element.GetRequiredString(JsonPropertyNames.Name, Subject);
        string context = $"Example field '{name}'";

        FieldType type = element.GetRequiredFieldType(context);

        // A missing "value" property is treated like an explicit null: the value is optional.
        element.TryGetProperty(JsonPropertyNames.Value, out JsonElement valueElement);

        FieldValue value;
        try
        {
            value = FieldValue.ReadJson(type, valueElement);
        }
        catch (JsonException ex)
        {
            throw new JsonException($"{context}: {ex.Message}", ex);
        }

        return Materialize(context, () => new ExampleField(name, type, value));
    }

    protected override void WriteCore(Utf8JsonWriter writer, ExampleField value, JsonSerializerOptions options)
    {
        writer.WriteString(JsonPropertyNames.Name, value.Name);
        writer.WriteString(JsonPropertyNames.Type, FieldTypes.GetWireName(value.Type));
        writer.WritePropertyName(JsonPropertyNames.Value);
        value.Value.WriteJson(writer);
    }
}
