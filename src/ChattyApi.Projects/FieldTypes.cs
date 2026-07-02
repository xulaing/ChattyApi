namespace ChattyApi.Projects;

/// <summary>
/// Single source of truth for the mapping between <see cref="FieldType"/> members,
/// their JSON wire names and their UI display names. All parsing and formatting of
/// field types anywhere in the codebase goes through this class.
/// </summary>
public static class FieldTypes
{
    /// <summary>Human-readable list of the supported wire names, used in error messages.</summary>
    public const string SupportedNames = "'string', 'number', 'date', 'boolean', 'list'";

    private static readonly Dictionary<string, FieldType> ByWireName = new(StringComparer.Ordinal)
    {
        ["string"] = FieldType.String,
        ["number"] = FieldType.Number,
        ["date"] = FieldType.Date,
        ["boolean"] = FieldType.Boolean,
        ["list"] = FieldType.List,
    };

    private static readonly Dictionary<FieldType, string> WireNames = new()
    {
        [FieldType.String] = "string",
        [FieldType.Number] = "number",
        [FieldType.Date] = "date",
        [FieldType.Boolean] = "boolean",
        [FieldType.List] = "list",
    };

    private static readonly Dictionary<FieldType, string> DisplayNames = new()
    {
        [FieldType.String] = "String",
        [FieldType.Number] = "Number",
        [FieldType.Date] = "Date",
        [FieldType.Boolean] = "Boolean",
        [FieldType.List] = "List",
    };

    /// <summary>All supported field types, in a stable order suitable for UI binding (combo boxes, ...).</summary>
    public static IReadOnlyList<FieldType> All { get; } = new[]
    {
        FieldType.String,
        FieldType.Number,
        FieldType.Date,
        FieldType.Boolean,
        FieldType.List,
    };

    /// <summary>Returns the JSON wire name of a field type (e.g. "string").</summary>
    public static string GetWireName(FieldType type)
    {
        if (!WireNames.TryGetValue(type, out string? wireName))
        {
            throw new ProjectValidationException(
                $"'{(int)type}' is not a supported field type. Supported types are: {SupportedNames}.");
        }

        return wireName;
    }

    /// <summary>Returns the display name of a field type (e.g. "String"), suitable for the UI.</summary>
    public static string GetDisplayName(FieldType type)
    {
        if (!DisplayNames.TryGetValue(type, out string? displayName))
        {
            throw new ProjectValidationException(
                $"'{(int)type}' is not a supported field type. Supported types are: {SupportedNames}.");
        }

        return displayName;
    }

    /// <summary>Attempts to parse a JSON wire name (e.g. "number") into a <see cref="FieldType"/>.</summary>
    public static bool TryParse(string? wireName, out FieldType type)
    {
        if (wireName is not null && ByWireName.TryGetValue(wireName, out type))
        {
            return true;
        }

        type = default;
        return false;
    }

    /// <summary>Parses a JSON wire name into a <see cref="FieldType"/>, throwing a descriptive exception on failure.</summary>
    public static FieldType Parse(string? wireName)
    {
        if (!TryParse(wireName, out FieldType type))
        {
            throw new ProjectValidationException(
                $"'{wireName}' is not a supported field type. Supported types are: {SupportedNames}.");
        }

        return type;
    }
}
