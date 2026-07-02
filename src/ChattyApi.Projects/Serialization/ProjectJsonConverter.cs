using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Wire format:
/// <code>
/// {
///   "name": "My project",
///   "schema": { "fields": [ ... ] },
///   "examples": [ { "values": [ ... ] }, ... ]
/// }
/// </code>
/// On read, every example is validated against the schema (missing/extra fields,
/// type mismatches) before the project is returned.
/// </summary>
public sealed class ProjectJsonConverter : JsonObjectConverter<Project>
{
    protected override string Subject => "Project";

    protected override Project ReadCore(JsonElement element, JsonSerializerOptions options)
    {
        string name = element.GetRequiredString(JsonPropertyNames.Name, Subject);
        string context = $"Project '{name}'";

        JsonElement schemaElement = element.GetRequiredProperty(JsonPropertyNames.Schema, context);
        ProjectSchema? schema;
        try
        {
            schema = schemaElement.Deserialize<ProjectSchema>(options);
        }
        catch (JsonException ex)
        {
            throw new JsonException($"{context}: {ex.Message}", ex);
        }

        if (schema is null)
        {
            throw new JsonException($"{context}: required property '{JsonPropertyNames.Schema}' is missing or null.");
        }

        var examples = new List<ProjectExample>();
        if (element.TryGetProperty(JsonPropertyNames.Examples, out JsonElement examplesElement)
            && examplesElement.ValueKind != JsonValueKind.Null)
        {
            if (examplesElement.ValueKind != JsonValueKind.Array)
            {
                throw new JsonException(
                    $"{context}: property '{JsonPropertyNames.Examples}' must be a JSON array but was '{examplesElement.ValueKind}'.");
            }

            int index = 0;
            foreach (JsonElement exampleElement in examplesElement.EnumerateArray())
            {
                index++;
                try
                {
                    ProjectExample? example = exampleElement.Deserialize<ProjectExample>(options);
                    examples.Add(example ?? throw new JsonException("the example is null."));
                }
                catch (JsonException ex)
                {
                    throw new JsonException($"{context}, example #{index}: {ex.Message}", ex);
                }
            }
        }

        return Materialize(context, () => new Project(name, schema, examples));
    }

    protected override void WriteCore(Utf8JsonWriter writer, Project value, JsonSerializerOptions options)
    {
        writer.WriteString(JsonPropertyNames.Name, value.Name);

        writer.WritePropertyName(JsonPropertyNames.Schema);
        JsonSerializer.Serialize(writer, value.Schema, options);

        writer.WriteStartArray(JsonPropertyNames.Examples);
        foreach (ProjectExample example in value.Examples)
        {
            JsonSerializer.Serialize(writer, example, options);
        }

        writer.WriteEndArray();
    }
}
