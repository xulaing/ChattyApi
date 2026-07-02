using ChattyApi.Projects.Values;

namespace ChattyApi.Projects;

/// <summary>
/// One field of the expected output structure: a name, a type and a description.
/// Immutable and always valid once constructed.
/// </summary>
public sealed class FieldDefinition
{
    public FieldDefinition(string name, FieldType type, string description)
    {
        Name = Guard.NotNullOrWhiteSpace(name, "Field name");
        Type = Guard.DefinedFieldType(type);
        Description = Guard.NotNullOrWhiteSpace(description, $"Description of field '{name}'");
    }

    /// <summary>The unique field name. Never null or empty.</summary>
    public string Name { get; }

    /// <summary>The field type. Always one of the supported types.</summary>
    public FieldType Type { get; }

    /// <summary>The field description. Never null or empty.</summary>
    public string Description { get; }

    /// <summary>Creates an empty (null) value slot matching this field's type.</summary>
    public FieldValue CreateEmptyValue() => FieldValue.CreateNull(Type);

    public override string ToString() => $"{Name} ({FieldTypes.GetWireName(Type)})";
}
