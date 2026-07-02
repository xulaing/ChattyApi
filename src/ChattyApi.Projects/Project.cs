using System.Text.Json.Serialization;
using ChattyApi.Projects.Serialization;

namespace ChattyApi.Projects;

/// <summary>
/// A project: an expected output structure plus a collection of examples that
/// all conform to that structure. The invariant "every example matches the
/// structure" is enforced on construction and whenever an example is added.
/// </summary>
[JsonConverter(typeof(ProjectJsonConverter))]
public sealed class Project
{
    private readonly List<ProjectExample> _examples = new();

    public Project(string name, ProjectSchema schema, IEnumerable<ProjectExample>? examples = null)
    {
        Name = Guard.NotNullOrWhiteSpace(name, "Project name");
        Schema = Guard.NotNull(schema, "The expected output structure");

        if (examples is not null)
        {
            foreach (ProjectExample example in examples)
            {
                AddExample(example);
            }
        }
    }

    /// <summary>The project name. Never null or empty.</summary>
    public string Name { get; }

    /// <summary>The expected output structure.</summary>
    public ProjectSchema Schema { get; }

    /// <summary>The input/output examples. Each one matches <see cref="Schema"/>.</summary>
    public IReadOnlyList<ProjectExample> Examples => _examples;

    /// <summary>Creates a new empty example matching the structure and adds it to the project.</summary>
    public ProjectExample AddExample()
    {
        ProjectExample example = ProjectExample.CreateFor(Schema);
        _examples.Add(example);
        return example;
    }

    /// <summary>Adds an existing example after verifying it matches the structure.</summary>
    public void AddExample(ProjectExample example)
    {
        Guard.NotNull(example, "The example");
        example.EnsureMatches(Schema);
        _examples.Add(example);
    }

    public bool RemoveExample(ProjectExample example) => _examples.Remove(example);
}
