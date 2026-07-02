namespace ChattyApi.Projects;

/// <summary>
/// Base class for all exceptions raised by the project model.
/// Catch this type to handle any model, validation or serialization failure uniformly.
/// </summary>
public abstract class ProjectModelException : Exception
{
    protected ProjectModelException(string message)
        : base(message)
    {
    }

    protected ProjectModelException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Thrown when a model object is built or mutated with invalid data
/// (empty field name, unsupported type, malformed list JSON, schema mismatch, ...).
/// </summary>
public sealed class ProjectValidationException : ProjectModelException
{
    public ProjectValidationException(string message)
        : base(message)
    {
    }

    public ProjectValidationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Thrown when JSON serialization or deserialization fails.
/// The message always explains what is wrong with the JSON payload.
/// </summary>
public sealed class ProjectSerializationException : ProjectModelException
{
    public ProjectSerializationException(string message)
        : base(message)
    {
    }

    public ProjectSerializationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
