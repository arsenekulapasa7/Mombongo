namespace SyncProject.Models;

public class SynchronizeModel
{
    public string ServerConnexionString{get;set;}
    public string LocalDb{get;set;}
    public string FileName{get;set;}

    public SynchronizeModel()
    {
        if(ServerConnexionString == null)
        {
            ServerConnexionString = "";
        }
        if(LocalDb == null)
        {
            LocalDb = "";
        }
        if(FileName == null)
        {
            FileName = "";
        }
    }
}