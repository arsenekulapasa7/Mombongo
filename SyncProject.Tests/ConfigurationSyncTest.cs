using Microsoft.AspNetCore.Mvc.Testing;
using SyncProject.Dtos;
using System.Net;
using System.Text;
using System.Text.Json;

namespace SyncProject.Tests;

public class ConfigurationSyncTest : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public ConfigurationSyncTest(WebApplicationFactory<Program> factory)
    {
        // Crée le client HTTP lié au serveur en mémoire
        _client = factory.CreateClient();
    }


    [Fact]
    public async Task Get_SetConfiguration_RetourneCodeOkEtContenuValide()
    {
        // Preparation of the payload
        // 1. Define your custom C# object
        var myObject = new SynchronizeDto { FileName = "tables.txt", 
            ConfigurationTableFile = new List<string> {"tUtilisateur", "tDepot", "tStock", "tCategorie"}
        };

        // 2. Serialize the object into a raw JSON string
        string jsonString = JsonSerializer.Serialize(myObject);

        // 3. Wrap the string inside an HttpContent object
        using HttpContent content = new StringContent(jsonString, Encoding.UTF8, "application/json");



        // Act : Envoi d'une requête HTTP GET vers l'endpoint de l'API
        // (SetConfiguration "/ConfigurationSync/SetConfiguration" par une route existante de votre API)
        HttpResponseMessage response = await _client.PostAsync("/ConfigurationSync/SetConfiguration", content);

        // Assert 1 : Vérifie que le code HTTP est 200 OK
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);


        string responseBody = await response.Content.ReadAsStringAsync();
        Console.WriteLine("Post written successfully");
        Console.WriteLine(responseBody);
        
    }
}
