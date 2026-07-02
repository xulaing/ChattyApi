using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// The single entry point for converting the project model to and from JSON.
/// All failures surface as <see cref="ProjectSerializationException"/> with a message
/// explaining exactly what is wrong (the converters embed the offending field or
/// example in the message).
/// </summary>
public static class ProjectJsonSerializer
{
    // Options are cached and reused: JsonSerializerOptions instances are expensive to
    // build and thread-safe to share, so this keeps serialization allocation-light.
    private static readonly JsonSerializerOptions WriteOptions = new() { WriteIndented = true };
    private static readonly JsonSerializerOptions ReadOptions = new();

    /// <summary>Serializes a full project (structure + examples) to indented JSON.</summary>
    public static string Serialize(Project project) => SerializeCore(project, "project");

    /// <summary>Serializes the expected output structure to indented JSON.</summary>
    public static string Serialize(ProjectSchema schema) => SerializeCore(schema, "expected output structure");

    /// <summary>Serializes a single example to indented JSON.</summary>
    public static string Serialize(ProjectExample example) => SerializeCore(example, "example");

    /// <summary>Deserializes a full project, validating the structure, every example and every value.</summary>
    public static Project DeserializeProject(string json) => DeserializeCore<Project>(json, "project");

    /// <summary>Deserializes an expected output structure.</summary>
    public static ProjectSchema DeserializeSchema(string json) =>
        DeserializeCore<ProjectSchema>(json, "expected output structure");

    /// <summary>
    /// Deserializes a single example. When <paramref name="schema"/> is provided, the
    /// example is also validated against it (field names and types must match).
    /// </summary>
    public static ProjectExample DeserializeExample(string json, ProjectSchema? schema = null)
    {
        ProjectExample example = DeserializeCore<ProjectExample>(json, "example");

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

    private static string SerializeCore<T>(T value, string subject)
        where T : class
    {
        Guard.NotNull(value, $"The {subject} to serialize");

        try
        {
            return JsonSerializer.Serialize(value, WriteOptions);
        }
        catch (JsonException ex)
        {
            throw new ProjectSerializationException($"Failed to serialize the {subject}: {ex.Message}", ex);
        }
    }

    private static T DeserializeCore<T>(string json, string subject)
        where T : class
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            throw new ProjectSerializationException(
                $"Cannot deserialize the {subject}: the JSON input is null or empty.");
        }

        try
        {
            T? result = JsonSerializer.Deserialize<T>(json, ReadOptions);

            return result ?? throw new ProjectSerializationException(
                $"Cannot deserialize the {subject}: the JSON input is the literal 'null'.");
        }
        catch (JsonException ex)
        {
            throw new ProjectSerializationException($"The {subject} JSON is invalid: {ex.Message}", ex);
        }
    }
}
