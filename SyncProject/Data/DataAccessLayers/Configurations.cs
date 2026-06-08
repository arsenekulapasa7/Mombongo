namespace SyncProject.Data.DataAccessLayers;

public class Configurations : IDisposable
{
    private readonly StreamReader _streamreader;

    public Configurations(string filePath)
    {
        _streamreader = new StreamReader(filePath);
    }

    public void Dispose()
    {
        _streamreader.Dispose();
    }

    public string? ReadLineNumber(int lineNumber)
    {
        _streamreader.DiscardBufferedData();
        _streamreader.BaseStream.Seek(0, SeekOrigin.Begin);


        string? textRead = "";
        for(var i = 0; i < lineNumber -1; ++i)
        {
            textRead = _streamreader.ReadLine();
        }

        return textRead;
    }

    public List<string> ReadAllLines()
    {
        var result = new List<string>();
        string? textValue = "";
        while (!_streamreader.EndOfStream)
        {
            textValue = _streamreader.ReadLine();
            if(textValue != null)
            {
                result.Add(textValue);
            }
        }

        return result;
    }
}