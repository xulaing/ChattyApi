namespace ChattyApi.Projects.Serialization;

/// <summary>The JSON property names of the wire format, in one place to avoid typos and drift.</summary>
internal static class JsonPropertyNames
{
    public const string Name = "name";
    public const string Type = "type";
    public const string Description = "description";
    public const string Value = "value";
    public const string Fields = "fields";
    public const string Values = "values";
    public const string Schema = "schema";
    public const string Examples = "examples";
}
