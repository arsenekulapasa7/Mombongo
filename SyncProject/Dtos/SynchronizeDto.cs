namespace SyncProject.Dtos;

public class SynchronizeDto
{
    public string FileName{get;set;}
    public List<string> ConfigurationTableFile{get;set;}

    public SynchronizeDto()
    {
        if(FileName == null)
        {
            FileName = "";
        }
        if(ConfigurationTableFile == null)
        {
            ConfigurationTableFile = new List<string>();
        }
    }
}