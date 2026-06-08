

using Microsoft.AspNetCore.Mvc.Testing;
using SyncProject.Dtos;
using SyncProject.Models;
using System.Net;
using System.Text;
using System.Text.Json;

namespace SyncProject.Tests;

public class SynchronizeSyncTest : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public SynchronizeSyncTest(WebApplicationFactory<Program> factory)
    {
        // Crée le client HTTP lié au serveur en mémoire
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Get_Synchronize_RetourneCodeOkEtContenuValide()
    {
        // Preparation of the payload
        // 1. Define your custom C# object
        var myObject = new SynchronizeModel
        {
            ServerConnexionString = "Data Source=SQL5083.site4now.net;Initial Catalog=db_a54efd_synchronizedb;User Id=db_a54efd_synchronizedb_admin;Password=12345678GL;Encrypt=True;TrustServerCertificate=True;",
            LocalDb = "table.db",
            FileName = "tables.txt",
        };

        // 2. Serialize the object into a raw JSON string
        string jsonString = JsonSerializer.Serialize(myObject);

        // 3. Wrap the string inside an HttpContent object
        using HttpContent content = new StringContent(jsonString, Encoding.UTF8, "application/json");



        // Act : Envoi d'une requête HTTP GET vers l'endpoint de l'API
        // (Synchronize "/SynchronizeSync/Synchronization" par une route existante de votre API)
        HttpResponseMessage response = await _client.PostAsync("/SynchronizeSync/Synchronization", content);

        // Assert 1 : Vérifie que le code HTTP est 200 OK
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);


        string responseBody = await response.Content.ReadAsStringAsync();
        Console.WriteLine("Data base has been Synchronized successfully");
        Console.WriteLine(responseBody);

    }
}
