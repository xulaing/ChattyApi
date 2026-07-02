namespace ChattyApi.Projects;

/// <summary>
/// Centralized argument validation. Every model class funnels its checks through
/// these helpers so validation messages stay consistent across the codebase.
/// </summary>
internal static class Guard
{
    /// <summary>Ensures a string is neither null, empty nor whitespace-only.</summary>
    public static string NotNullOrWhiteSpace(string? value, string subject)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ProjectValidationException($"{subject} cannot be null or empty.");
        }

        return value;
    }

    /// <summary>Ensures a reference is not null.</summary>
    public static T NotNull<T>(T? value, string subject)
        where T : class
    {
        if (value is null)
        {
            throw new ProjectValidationException($"{subject} cannot be null.");
        }

        return value;
    }

    /// <summary>Ensures the value is one of the declared <see cref="FieldType"/> members (guards against casts from arbitrary integers).</summary>
    public static FieldType DefinedFieldType(FieldType type)
    {
        if (!Enum.IsDefined(type))
        {
            throw new ProjectValidationException(
                $"'{(int)type}' is not a supported field type. Supported types are: {FieldTypes.SupportedNames}.");
        }

        return type;
    }
}
