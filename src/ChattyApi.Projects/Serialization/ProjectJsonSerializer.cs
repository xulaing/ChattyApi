using System.Text;
using System.Text.Json;
using ChattyApi.Projects.Values;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// The single entry point for converting the project model to and from JSON.
/// The whole wire format lives in this file: the Write* methods produce the JSON,
/// the Read* methods parse and validate it. All failures surface as
/// <see cref="ProjectSerializationException"/> with a message explaining exactly
/// what is wrong (offending field, example index, property, ...).
/// </summary>
public static class ProjectJsonSerializer
{
    private static readonly JsonWriterOptions IndentedWriterOptions = new() { Indented = true };

    // ----- Serialization (objects -> JSON) -----

    /// <summary>Serializes a full project (structure + examples) to indented JSON.</summary>
    public static string Serialize(Project project)
    {
        Guard.NotNull(project, "The project to serialize");
        return WriteToString(writer => WriteProject(writer, project));
    }

    /// <summary>Serializes the expected output structure to indented JSON.</summary>
    public static string Serialize(ProjectSchema schema)
    {
        Guard.NotNull(schema, "The expected output structure to serialize");
        return WriteToString(writer => WriteSchema(writer, schema));
    }

    /// <summary>Serializes a single example to indented JSON.</summary>
    public static string Serialize(ProjectExample example)
    {
        Guard.NotNull(example, "The example to serialize");
        return WriteToString(writer => WriteExample(writer, example));
    }

    private static string WriteToString(Action<Utf8JsonWriter> write)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, IndentedWriterOptions))
        {
            write(writer);
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private static void WriteProject(Utf8JsonWriter writer, Project project)
    {
        writer.WriteStartObject();
        writer.WriteString("name", project.Name);

        writer.WritePropertyName("schema");
        WriteSchema(writer, project.Schema);

        writer.WriteStartArray("examples");
        foreach (ProjectExample example in project.Examples)
        {
            WriteExample(writer, example);
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
    }

    private static void WriteSchema(Utf8JsonWriter writer, ProjectSchema schema)
    {
        writer.WriteStartObject();
        writer.WriteStartArray("fields");

        foreach (FieldDefinition field in schema.Fields)
        {
            writer.WriteStartObject();
            writer.WriteString("name", field.Name);
            writer.WriteString("type", FieldTypes.GetWireName(field.Type));
            writer.WriteString("description", field.Description);
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
    }

    private static void WriteExample(Utf8JsonWriter writer, ProjectExample example)
    {
        writer.WriteStartObject();
        writer.WriteStartArray("values");

        foreach (ExampleField field in example.Fields)
        {
            writer.WriteStartObject();
            writer.WriteString("name", field.Name);
            writer.WriteString("type", FieldTypes.GetWireName(field.Type));
            writer.WritePropertyName("value");
            field.Value.WriteJson(writer); // each value kind writes its native JSON type
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
    }

    // ----- Deserialization (JSON -> objects) -----

    /// <summary>Deserializes a full project, validating the structure, every example and every value.</summary>
    public static Project DeserializeProject(string json) =>
        Deserialize(json, "project", ReadProject);

    /// <summary>Deserializes an expected output structure.</summary>
    public static ProjectSchema DeserializeSchema(string json) =>
        Deserialize(json, "expected output structure", ReadSchema);

    /// <summary>
    /// Deserializes a single example. When <paramref name="schema"/> is provided, the
    /// example is also validated against it (field names and types must match).
    /// </summary>
    public static ProjectExample DeserializeExample(string json, ProjectSchema? schema = null)
    {
        ProjectExample example = Deserialize(json, "example", ReadExample);

        if (schema is not null)
        {
            try
            {
                example.EnsureMatches(schema);
            }
            catch (ProjectValidationException ex)
            {
                throw new ProjectSerializationException($"The example JSON is invalid: {ex.Message}", ex);
            }
        }

        return example;
    }

    private static T Deserialize<T>(string json, string subject, Func<JsonElement, T> read)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            throw new ProjectSerializationException(
                $"Cannot deserialize the {subject}: the JSON input is null or empty.");
        }

        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            return read(document.RootElement);
        }
        catch (JsonException ex)
        {
            throw new ProjectSerializationException($"The {subject} JSON is invalid: {ex.Message}", ex);
        }
        catch (ProjectValidationException ex)
        {
            // Model constructors reject invalid data (duplicate names, schema mismatches, ...).
            throw new ProjectSerializationException($"The {subject} JSON is invalid: {ex.Message}", ex);
        }
    }

    private static Project ReadProject(JsonElement element)
    {
        ExpectObject(element, "Project");
        string name = GetRequiredString(element, "name", "Project");
        string context = $"Project '{name}'";

        ProjectSchema schema = ReadSchema(GetRequiredProperty(element, "schema", context));

        var examples = new List<ProjectExample>();
        if (element.TryGetProperty("examples", out JsonElement examplesElement)
            && examplesElement.ValueKind != JsonValueKind.Null)
        {
            if (examplesElement.ValueKind != JsonValueKind.Array)
            {
                throw new JsonException(
                    $"{context}: property 'examples' must be a JSON array but was '{examplesElement.ValueKind}'.");
            }

            int index = 0;
            foreach (JsonElement exampleElement in examplesElement.EnumerateArray())
            {
                index++;
                try
                {
                    examples.Add(ReadExample(exampleElement));
                }
                catch (JsonException ex)
                {
                    throw new JsonException($"{context}, example #{index}: {ex.Message}", ex);
                }
            }
        }

        return new Project(name, schema, examples);
    }

    private static ProjectSchema ReadSchema(JsonElement element)
    {
        const string context = "Expected output structure";
        ExpectObject(element, context);
        JsonElement fieldsElement = GetRequiredArray(element, "fields", context);

        var fields = new List<FieldDefinition>();
        int index = 0;
        foreach (JsonElement fieldElement in fieldsElement.EnumerateArray())
        {
            index++;
            try
            {
                fields.Add(ReadFieldDefinition(fieldElement));
            }
            catch (JsonException ex)
            {
                throw new JsonException($"{context}, field #{index}: {ex.Message}", ex);
            }
        }

        return new ProjectSchema(fields);
    }

    private static FieldDefinition ReadFieldDefinition(JsonElement element)
    {
        ExpectObject(element, "Field definition");
        string name = GetRequiredString(element, "name", "Field definition");
        string context = $"Field definition '{name}'";

        FieldType type = GetRequiredFieldType(element, context);
        string description = GetRequiredString(element, "description", context);

        return new FieldDefinition(name, type, description);
    }

    private static ProjectExample ReadExample(JsonElement element)
    {
        const string context = "Example";
        ExpectObject(element, context);
        JsonElement valuesElement = GetRequiredArray(element, "values", context);

        var fields = new List<ExampleField>();
        int index = 0;
        foreach (JsonElement fieldElement in valuesElement.EnumerateArray())
        {
            index++;
            try
            {
                fields.Add(ReadExampleField(fieldElement));
            }
            catch (JsonException ex)
            {
                throw new JsonException($"{context}, value #{index}: {ex.Message}", ex);
            }
        }

        return new ProjectExample(fields);
    }

    private static ExampleField ReadExampleField(JsonElement element)
    {
        ExpectObject(element, "Example field");
        string name = GetRequiredString(element, "name", "Example field");
        string context = $"Example field '{name}'";

        FieldType type = GetRequiredFieldType(element, context);

        // A missing "value" property leaves valueElement 'Undefined', treated like null: the value is optional.
        element.TryGetProperty("value", out JsonElement valueElement);

        try
        {
            FieldValue value = FieldValue.ReadJson(type, valueElement);
            return new ExampleField(name, type, value);
        }
        catch (JsonException ex)
        {
            throw new JsonException($"{context}: {ex.Message}", ex);
        }
    }

    // ----- Shared JSON reading helpers (consistent, contextual error messages) -----

    private static void ExpectObject(JsonElement element, string context)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException($"{context}: expected a JSON object but found '{element.ValueKind}'.");
        }
    }

    private static JsonElement GetRequiredProperty(JsonElement element, string propertyName, string context)
    {
        if (!element.TryGetProperty(propertyName, out JsonElement property)
            || property.ValueKind == JsonValueKind.Null)
        {
            throw new JsonException($"{context}: required property '{propertyName}' is missing or null.");
        }

        return property;
    }

    private static string GetRequiredString(JsonElement element, string propertyName, string context)
    {
        JsonElement property = GetRequiredProperty(element, propertyName, context);

        if (property.ValueKind != JsonValueKind.String)
        {
            throw new JsonException(
                $"{context}: property '{propertyName}' must be a JSON string but was '{property.ValueKind}'.");
        }

        string value = property.GetString()!;
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new JsonException($"{context}: property '{propertyName}' cannot be empty.");
        }

        return value;
    }

    private static JsonElement GetRequiredArray(JsonElement element, string propertyName, string context)
    {
        JsonElement property = GetRequiredProperty(element, propertyName, context);

        if (property.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException(
                $"{context}: property '{propertyName}' must be a JSON array but was '{property.ValueKind}'.");
        }

        return property;
    }

    private static FieldType GetRequiredFieldType(JsonElement element, string context)
    {
        string wireName = GetRequiredString(element, "type", context);

        if (!FieldTypes.TryParse(wireName, out FieldType type))
        {
            throw new JsonException(
                $"{context}: '{wireName}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}.");
        }

        return type;
    }
}
