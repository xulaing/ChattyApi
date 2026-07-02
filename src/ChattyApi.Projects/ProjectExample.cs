using System.Text.Json.Serialization;
using ChattyApi.Projects.Serialization;
using ChattyApi.Projects.Values;

namespace ChattyApi.Projects;

/// <summary>
/// One input/output example. Its fields (names and types) mirror the project's
/// expected output structure; the user only fills in the values.
/// </summary>
[JsonConverter(typeof(ProjectExampleJsonConverter))]
public sealed class ProjectExample
{
    private readonly List<ExampleField> _fields;
    private readonly Dictionary<string, ExampleField> _fieldsByName;

    internal ProjectExample(IEnumerable<ExampleField> fields)
    {
        Guard.NotNull(fields, "The example field collection");

        _fields = new List<ExampleField>();
        _fieldsByName = new Dictionary<string, ExampleField>(StringComparer.Ordinal);

        foreach (ExampleField? item in fields)
        {
            ExampleField field = Guard.NotNull(item, "An example field");

            if (!_fieldsByName.TryAdd(field.Name, field))
            {
                throw new ProjectValidationException(
                    $"The example contains the field name '{field.Name}' more than once. Field names must be unique.");
            }

            _fields.Add(field);
        }
    }

    /// <summary>Creates an empty example whose fields (names and types) mirror the given structure.</summary>
    public static ProjectExample CreateFor(ProjectSchema schema)
    {
        Guard.NotNull(schema, "The expected output structure");

        return new ProjectExample(
            schema.Fields.Select(f => new ExampleField(f.Name, f.Type, f.CreateEmptyValue())));
    }

    /// <summary>The example fields, in the order defined by the expected structure.</summary>
    public IReadOnlyList<ExampleField> Fields => _fields;

    public int Count => _fields.Count;

    public bool TryGetField(string name, out ExampleField field)
    {
        if (name is not null && _fieldsByName.TryGetValue(name, out ExampleField? found))
        {
            field = found;
            return true;
        }

        field = null!;
        return false;
    }

    /// <summary>Returns the field with the given name, or throws listing the known field names.</summary>
    public ExampleField GetField(string name)
    {
        if (!TryGetField(name, out ExampleField field))
        {
            string known = _fields.Count == 0
                ? "(the example has no fields)"
                : string.Join(", ", _fields.Select(f => $"'{f.Name}'"));

            throw new ProjectValidationException(
                $"The example has no field named '{name}'. Known fields: {known}.");
        }

        return field;
    }

    /// <summary>Sets the value of the named field. The value's type must match the field type.</summary>
    public void SetValue(string fieldName, FieldValue value) => GetField(fieldName).SetValue(value);

    /// <summary>
    /// Verifies that this example structurally matches the expected output structure
    /// (same field names and types, no missing or extra fields).
    /// </summary>
    public void EnsureMatches(ProjectSchema schema)
    {
        Guard.NotNull(schema, "The expected output structure");

        foreach (FieldDefinition definition in schema.Fields)
        {
            if (!TryGetField(definition.Name, out ExampleField field))
            {
                throw new ProjectValidationException(
                    $"The example does not match the expected output structure: field '{definition.Name}' is missing.");
            }

            if (field.Type != definition.Type)
            {
                throw new ProjectValidationException(
                    $"The example does not match the expected output structure: field '{definition.Name}' has type " +
                    $"'{FieldTypes.GetWireName(field.Type)}' but the structure defines it as '{FieldTypes.GetWireName(definition.Type)}'.");
            }
        }

        foreach (ExampleField field in _fields)
        {
            if (!schema.ContainsField(field.Name))
            {
                throw new ProjectValidationException(
                    $"The example does not match the expected output structure: it contains an unknown field '{field.Name}'.");
            }
        }
    }
}
