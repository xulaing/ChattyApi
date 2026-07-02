using System.Text.Json;

namespace ChattyApi.Projects.Values;

/// <summary>
/// The strongly typed value of a single example field.
/// Each concrete subclass owns the JSON reading/writing rules for its <see cref="FieldType"/>,
/// which guarantees that JSON types are strictly preserved (numbers stay numbers,
/// booleans stay booleans, lists are written as real JSON arrays, ...).
/// Instances are immutable; to change a field's value, assign a new <see cref="FieldValue"/>.
/// </summary>
public abstract class FieldValue
{
    // Restricts subclassing to this assembly so the set of value kinds stays closed
    // and in sync with FieldType.
    private protected FieldValue()
    {
    }

    /// <summary>The field type this value belongs to.</summary>
    public abstract FieldType Type { get; }

    /// <summary>False when the value is null/unset (always allowed for example values).</summary>
    public abstract bool HasValue { get; }

    /// <summary>Creates the null (unset) value for the given field type.</summary>
    public static FieldValue CreateNull(FieldType type)
    {
        Guard.DefinedFieldType(type);

        return type switch
        {
            FieldType.String => StringFieldValue.Null,
            FieldType.Number => NumberFieldValue.Null,
            FieldType.Date => DateFieldValue.Null,
            FieldType.Boolean => BooleanFieldValue.Null,
            FieldType.List => ListFieldValue.Null,
            _ => throw new ProjectValidationException(
                $"'{type}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}."),
        };
    }

    /// <summary>
    /// Reads a JSON value for the given field type, enforcing the JSON kind expected by that type.
    /// Throws <see cref="JsonException"/> with a precise message when the JSON kind does not match.
    /// </summary>
    internal static FieldValue ReadJson(FieldType type, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return CreateNull(type);
        }

        return type switch
        {
            FieldType.String => StringFieldValue.ReadJson(value),
            FieldType.Number => NumberFieldValue.ReadJson(value),
            FieldType.Date => DateFieldValue.ReadJson(value),
            FieldType.Boolean => BooleanFieldValue.ReadJson(value),
            FieldType.List => ListFieldValue.ReadJson(value),
            _ => throw new JsonException(
                $"'{type}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}."),
        };
    }

    /// <summary>Writes this value to the writer using its native JSON representation.</summary>
    internal abstract void WriteJson(Utf8JsonWriter writer);
}
