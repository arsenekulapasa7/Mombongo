using Dotmim.Sync;
using Dotmim.Sync.Sqlite;
using Dotmim.Sync.SqlServer;
using SyncProject.Dtos;
using SyncProject.Models;

namespace SyncProject.Data.DataAccessLayers;

public static class SynchronizeAccessLayer
{

    /// <summary>
    /// ConfigurationAsync method do the configuration, and it's used once only
    /// </summary>
    /// <param name="modelDto"></param>
    /// <returns></returns>
    public static async Task ConfigurationAsync(SynchronizeDto modelDto)
    {
        // WRITE THE TABLES CONFIG

        // const string filePath = "tables.txt";

        using (var configWriteTables = new TablesConfiguration(modelDto.FileName)) // filePath
        {
            configWriteTables.WriteConfiguration(modelDto.ConfigurationTableFile);
        }
    }


    /// <summary>
    /// SynchronizeAsync method do the sync every 5min
    /// </summary>
    /// <param name="model"></param>
    /// <returns></returns>
    public static async Task SynchronizeAsync(SynchronizeModel model)
    {
        var serverProvider = new SqlSyncProvider(model.ServerConnexionString); // GetDatabaseConnectionString(AdventureWorks)
        var clientProvider = new SqliteSyncProvider(model.LocalDb); // "advworks.db"


        
        // READ THE TABLES CONFIG ALL READY IN THE FILE

        List<string> tablesList =  new List<string>();
        using (var configReadTables = new Configurations(model.FileName))
        {
            tablesList = configReadTables.ReadAllLines();
        }


        var setup = new SyncSetup(tablesList);

        var agent = new SyncAgent(clientProvider, serverProvider);

        var progress = new SynchronousProgress<ProgressArgs>(s => 
                Console.WriteLine($"{s.Context.SyncStage}:\t{s.Message}"));



        Console.Clear();
        Console.WriteLine("Sync Start");

        try
        {
            var syncContext = await agent.SynchronizeAsync(setup, progress);
            Console.WriteLine(syncContext);
        }
        catch (Exception e)
        {
            Console.WriteLine(e.Message);
        }


        // do
        // {
        //     // Console.Clear();
        //     // Console.WriteLine("Sync Start");
            

        //     await Task.Delay(TimeSpan.FromMinutes(5)); 

        // } while (true); // Console.ReadKey().Key != ConsoleKey.Escape
    }
}