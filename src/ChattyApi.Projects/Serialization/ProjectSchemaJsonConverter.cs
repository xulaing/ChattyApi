using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Wire format: <c>{ "fields": [ { "name": ..., "type": ..., "description": ... }, ... ] }</c>.
/// An array (rather than an object keyed by field name) preserves the user-defined
/// field order and lets us reject duplicate names explicitly instead of silently
/// overwriting them.
/// </summary>
public sealed class ProjectSchemaJsonConverter : JsonObjectConverter<ProjectSchema>
{
    protected override string Subject => "Expected output structure";

    protected override ProjectSchema ReadCore(JsonElement element, JsonSerializerOptions options)
    {
        JsonElement fieldsElement = element.GetRequiredArray(JsonPropertyNames.Fields, Subject);

        var fields = new List<FieldDefinition>(fieldsElement.GetArrayLength());
        int index = 0;

        foreach (JsonElement fieldElement in fieldsElement.EnumerateArray())
        {
            index++;
            try
            {
                FieldDefinition? field = fieldElement.Deserialize<FieldDefinition>(options);
                fields.Add(field ?? throw new JsonException("the field definition is null."));
            }
            catch (JsonException ex)
            {
                throw new JsonException($"{Subject}, field #{index}: {ex.Message}", ex);
            }
        }

        return Materialize(Subject, () => new ProjectSchema(fields));
    }

    protected override void WriteCore(Utf8JsonWriter writer, ProjectSchema value, JsonSerializerOptions options)
    {
        writer.WriteStartArray(JsonPropertyNames.Fields);

        foreach (FieldDefinition field in value.Fields)
        {
            JsonSerializer.Serialize(writer, field, options);
        }

        writer.WriteEndArray();
    }
}
