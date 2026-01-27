
using Amazon.CognitoIdentityProvider;
using Microsoft.EntityFrameworkCore;
using RAG.APIs.Infrastructure;
using RAG.Application.Interfaces;
using RAG.Infrastructure.AWS;
using RAG.Infrastructure.Database;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.AddControllers();
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger(); 
    app.UseSwaggerUI(); 
}
//if (app.Environment.IsDevelopment())
//{
//    app.MapOpenApi();
//}

app.UseHttpsRedirection();

app.UseAuthorization();
 
app.MapControllers();

app.Run();
