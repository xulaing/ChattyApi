using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Wire format: <c>{ "values": [ { "name": ..., "type": ..., "value": ... }, ... ] }</c>.
/// </summary>
public sealed class ProjectExampleJsonConverter : JsonObjectConverter<ProjectExample>
{
    protected override string Subject => "Example";

    protected override ProjectExample ReadCore(JsonElement element, JsonSerializerOptions options)
    {
        JsonElement valuesElement = element.GetRequiredArray(JsonPropertyNames.Values, Subject);

        var fields = new List<ExampleField>(valuesElement.GetArrayLength());
        int index = 0;

        foreach (JsonElement fieldElement in valuesElement.EnumerateArray())
        {
            index++;
            try
            {
                ExampleField? field = fieldElement.Deserialize<ExampleField>(options);
                fields.Add(field ?? throw new JsonException("the example field is null."));
            }
            catch (JsonException ex)
            {
                throw new JsonException($"{Subject}, value #{index}: {ex.Message}", ex);
            }
        }

        return Materialize(Subject, () => new ProjectExample(fields));
    }

    protected override void WriteCore(Utf8JsonWriter writer, ProjectExample value, JsonSerializerOptions options)
    {
        writer.WriteStartArray(JsonPropertyNames.Values);

        foreach (ExampleField field in value.Fields)
        {
            JsonSerializer.Serialize(writer, field, options);
        }

        writer.WriteEndArray();
    }
}
