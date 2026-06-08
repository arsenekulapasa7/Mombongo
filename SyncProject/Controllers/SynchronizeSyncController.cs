using Microsoft.AspNetCore.Mvc;
using SyncProject.Data.DataAccessLayers;
using SyncProject.Models;

namespace SyncProject.Controllers;

[ApiController]
[Route("[controller]")]
public class SynchronizeSyncController
{

    [HttpPost("Synchronization")]
    public async Task Synchronization(SynchronizeModel model)
    {
        await SynchronizeAccessLayer.SynchronizeAsync(model);
    }
}