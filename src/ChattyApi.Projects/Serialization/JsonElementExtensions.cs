using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>
/// Shared helpers for reading required data out of a <see cref="JsonElement"/>
/// with consistent, contextual error messages. All converters use these instead
/// of duplicating property checks.
/// </summary>
internal static class JsonElementExtensions
{
    /// <summary>Returns the named property, throwing if it is missing or JSON null.</summary>
    public static JsonElement GetRequiredProperty(this JsonElement element, string propertyName, string context)
    {
        if (!element.TryGetProperty(propertyName, out JsonElement property)
            || property.ValueKind == JsonValueKind.Null)
        {
            throw new JsonException($"{context}: required property '{propertyName}' is missing or null.");
        }

        return property;
    }

    /// <summary>Returns the named property as a non-empty string, throwing a descriptive error otherwise.</summary>
    public static string GetRequiredString(this JsonElement element, string propertyName, string context)
    {
        JsonElement property = element.GetRequiredProperty(propertyName, context);

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

    /// <summary>Returns the named property as an array, throwing a descriptive error otherwise.</summary>
    public static JsonElement GetRequiredArray(this JsonElement element, string propertyName, string context)
    {
        JsonElement property = element.GetRequiredProperty(propertyName, context);

        if (property.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException(
                $"{context}: property '{propertyName}' must be a JSON array but was '{property.ValueKind}'.");
        }

        return property;
    }

    /// <summary>Parses the named property as a <see cref="FieldType"/> wire name.</summary>
    public static FieldType GetRequiredFieldType(this JsonElement element, string context)
    {
        string wireName = element.GetRequiredString(JsonPropertyNames.Type, context);

        if (!FieldTypes.TryParse(wireName, out FieldType type))
        {
            throw new JsonException(
                $"{context}: '{wireName}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}.");
        }

        return type;
    }
}
