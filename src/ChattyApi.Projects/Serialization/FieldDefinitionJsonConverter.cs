using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Wire format: <c>{ "name": "field1", "type": "string", "description": "..." }</c>.
/// </summary>
public sealed class FieldDefinitionJsonConverter : JsonObjectConverter<FieldDefinition>
{
    protected override string Subject => "Field definition";

    protected override FieldDefinition ReadCore(JsonElement element, JsonSerializerOptions options)
    {
        string name = element.GetRequiredString(JsonPropertyNames.Name, Subject);
        string context = $"Field definition '{name}'";

        FieldType type = element.GetRequiredFieldType(context);
        string description = element.GetRequiredString(JsonPropertyNames.Description, context);

        return Materialize(context, () => new FieldDefinition(name, type, description));
    }

    protected override void WriteCore(Utf8JsonWriter writer, FieldDefinition value, JsonSerializerOptions options)
    {
        writer.WriteString(JsonPropertyNames.Name, value.Name);
        writer.WriteString(JsonPropertyNames.Type, FieldTypes.GetWireName(value.Type));
        writer.WriteString(JsonPropertyNames.Description, value.Description);
    }
}
