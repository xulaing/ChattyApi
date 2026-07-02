using System.Text.Json.Serialization;
using ChattyApi.Projects.Serialization;
using ChattyApi.Projects.Values;

namespace ChattyApi.Projects;

/// <summary>
/// One field of an example. Its name and type are inherited from the expected output
/// structure and can never change or be null; only the value is editable, and the
/// value may be null.
/// </summary>
[JsonConverter(typeof(ExampleFieldJsonConverter))]
public sealed class ExampleField
{
    // Internal: instances are created from a ProjectSchema (ProjectExample.CreateFor)
    // or by the JSON converter, so name/type always come from a validated source.
    internal ExampleField(string name, FieldType type, FieldValue value)
    {
        Name = Guard.NotNullOrWhiteSpace(name, "Field name");
        Type = Guard.DefinedFieldType(type);
        Value = ValidateValue(value);
    }

    /// <summary>The field name, inherited from the expected structure. Never null.</summary>
    public string Name { get; }

    /// <summary>The field type, inherited from the expected structure. Never null.</summary>
    public FieldType Type { get; }

    /// <summary>The value entered by the user. <see cref="FieldValue.HasValue"/> is false when unset.</summary>
    public FieldValue Value { get; private set; }

    /// <summary>Replaces the value. The new value's type must match the field type.</summary>
    public void SetValue(FieldValue value) => Value = ValidateValue(value);

    /// <summary>Sets a string value. Only valid on 'string' fields.</summary>
    public void SetString(string? value) => SetValue(value is null ? StringFieldValue.Null : new StringFieldValue(value));

    /// <summary>Sets a numeric value. Only valid on 'number' fields.</summary>
    public void SetNumber(decimal? value) => SetValue(value is null ? NumberFieldValue.Null : new NumberFieldValue(value));

    /// <summary>Sets a date value. Only valid on 'date' fields.</summary>
    public void SetDate(DateTimeOffset? value) => SetValue(value is null ? DateFieldValue.Null : new DateFieldValue(value));

    /// <summary>Sets a boolean value. Only valid on 'boolean' fields.</summary>
    public void SetBoolean(bool? value) => SetValue(value is null ? BooleanFieldValue.Null : new BooleanFieldValue(value));

    /// <summary>
    /// Sets a list value from the text box content. Only valid on 'list' fields.
    /// The text must be a well-formed JSON array; a descriptive
    /// <see cref="ProjectValidationException"/> is thrown otherwise.
    /// </summary>
    public void SetListText(string? textBoxContent)
    {
        try
        {
            SetValue(ListFieldValue.Parse(textBoxContent));
        }
        catch (ProjectValidationException ex)
        {
            throw new ProjectValidationException($"Field '{Name}': {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Returns the list value as text for display in the text box (null when unset).
    /// Only valid on 'list' fields.
    /// </summary>
    public string? GetListText()
    {
        if (Value is not ListFieldValue list)
        {
            throw new ProjectValidationException(
                $"Field '{Name}' is of type '{FieldTypes.GetWireName(Type)}', not 'list'; it has no list text.");
        }

        return list.RawJson;
    }

    /// <summary>Resets the value to null.</summary>
    public void Clear() => Value = FieldValue.CreateNull(Type);

    private FieldValue ValidateValue(FieldValue value)
    {
        Guard.NotNull(value, $"The value holder of field '{Name}'");

        if (value.Type != Type)
        {
            throw new ProjectValidationException(
                $"Field '{Name}' is of type '{FieldTypes.GetWireName(Type)}' but received a value of type '{FieldTypes.GetWireName(value.Type)}'.");
        }

        return value;
    }

    public override string ToString() => $"{Name} ({FieldTypes.GetWireName(Type)})";
}
