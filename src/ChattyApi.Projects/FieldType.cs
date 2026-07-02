namespace ChattyApi.Projects;

/// <summary>
/// The type of a field in the expected output structure.
/// Serialized to JSON as its lowercase wire name ("string", "number", "date", "boolean", "list").
/// </summary>
public enum FieldType
{
    String,
    Number,
    Date,
    Boolean,
    List,
}
