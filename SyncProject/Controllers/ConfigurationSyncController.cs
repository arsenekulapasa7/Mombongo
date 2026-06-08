using Microsoft.AspNetCore.Mvc;
using SyncProject.Data.DataAccessLayers;
using SyncProject.Dtos;

namespace SyncProject.Controllers;

[ApiController]
[Route("[controller]")]
public class ConfigurationSyncController
{
    [HttpPost("SetConfiguration")]
    public async Task SetConfiguration(SynchronizeDto modelDto)
    {
        await SynchronizeAccessLayer.ConfigurationAsync(modelDto);
    }
}