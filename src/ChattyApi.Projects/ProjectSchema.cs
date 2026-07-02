namespace ChattyApi.Projects;

/// <summary>
/// The expected output structure of a project: an ordered collection of uniquely
/// named <see cref="FieldDefinition"/>s. Immutable and always valid once constructed.
/// </summary>
public sealed class ProjectSchema
{
    private readonly List<FieldDefinition> _fields;
    private readonly Dictionary<string, FieldDefinition> _fieldsByName;

    public ProjectSchema(IEnumerable<FieldDefinition> fields)
    {
        Guard.NotNull(fields, "The schema field collection");

        _fields = new List<FieldDefinition>();
        _fieldsByName = new Dictionary<string, FieldDefinition>(StringComparer.Ordinal);

        foreach (FieldDefinition? item in fields)
        {
            FieldDefinition field = Guard.NotNull(item, "A schema field");

            if (!_fieldsByName.TryAdd(field.Name, field))
            {
                throw new ProjectValidationException(
                    $"The expected output structure contains the field name '{field.Name}' more than once. Field names must be unique.");
            }

            _fields.Add(field);
        }
    }

    public ProjectSchema(params FieldDefinition[] fields)
        : this((IEnumerable<FieldDefinition>)fields)
    {
    }

    /// <summary>The fields, in the order the user defined them.</summary>
    public IReadOnlyList<FieldDefinition> Fields => _fields;

    public int Count => _fields.Count;

    public bool ContainsField(string name) => name is not null && _fieldsByName.ContainsKey(name);

    public bool TryGetField(string name, out FieldDefinition field)
    {
        if (name is not null && _fieldsByName.TryGetValue(name, out FieldDefinition? found))
        {
            field = found;
            return true;
        }

        field = null!;
        return false;
    }

    /// <summary>Returns the field with the given name, or throws listing the known field names.</summary>
    public FieldDefinition GetField(string name)
    {
        if (!TryGetField(name, out FieldDefinition field))
        {
            string known = _fields.Count == 0
                ? "(the structure has no fields)"
                : string.Join(", ", _fields.Select(f => $"'{f.Name}'"));

            throw new ProjectValidationException(
                $"The expected output structure has no field named '{name}'. Known fields: {known}.");
        }

        return field;
    }

    /// <summary>Creates a new empty example whose fields mirror this structure.</summary>
    public ProjectExample CreateExample() => ProjectExample.CreateFor(this);
}
