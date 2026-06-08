namespace SyncProject.Data.DataAccessLayers;

/// <summary>
/// This method does the configuration and it has to be used once.
/// Only when configuring the synchronization.
/// </summary>
public class TablesConfiguration : IDisposable
{
    public readonly StreamWriter _streamwriter;

    public TablesConfiguration(string filePath)
    {
        if (!File.Exists(filePath))
        {
            _streamwriter = new StreamWriter(filePath, true);
        }
        else
        {
            File.WriteAllText(filePath, string.Empty);
            _streamwriter = new StreamWriter(filePath, true);
        }
    }

    public void Dispose()
    {
        _streamwriter.Dispose();
    }

    public  void WriteConfiguration(List<string> tables)
    {
        foreach(var tableValue in tables)
        {
            _streamwriter.WriteLine($"{tableValue + Environment.NewLine}");
        }
        _streamwriter.Flush();
        
    }
}