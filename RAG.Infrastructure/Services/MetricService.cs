using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Domain.DTOs.Metric;
using RAG.Infrastructure.Database;
using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace RAG.Infrastructure.Services
{
    public class MetricService : IMetricService
    {
        private readonly ApplicationDbContext _dbContext;

        public MetricService(ApplicationDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task<GetMetricGroupsResponse> GetMetricGroupsAsync()
        {
            var groups = await _dbContext.RatioGroups
                .Select(g => new MetricGroupDto
                {
                    Id = g.Id,
                    Name = g.Name ?? string.Empty,
                    Description = g.Description ?? string.Empty
                })
                .ToListAsync();

            return new GetMetricGroupsResponse
            {
                Groups = groups
            };
        }

        public async Task<GetMetricDefinitionsResponse> GetMetricDefinitionsAsync(Guid? groupId)
        {
            var query = _dbContext.RatioDefinitions.Include(d => d.Group).AsQueryable();

            if (groupId.HasValue)
            {
                query = query.Where(d => d.Groupid == groupId.Value);
            }

            var definitions = await query
                .Select(d => new MetricDefinitionDto
                {
                    Id = d.Id,
                    Code = d.Code ?? string.Empty,
                    Name = d.Name ?? string.Empty,
                    Formula = d.Formula ?? string.Empty,
                    Unit = d.Unit ?? string.Empty,
                    GroupName = d.Group != null ? d.Group.Name : string.Empty
                })
                .ToListAsync();

            return new GetMetricDefinitionsResponse
            {
                Definitions = definitions
            };
        }

        public async Task<GetMetricValuesByReportResponse> GetMetricValuesByReportAsync(Guid reportId)
        {
            var values = await _dbContext.RatioValues
                .Include(v => v.Definition)
                .Where(v => v.Reportid == reportId)
                .Select(v => new MetricValueDto
                {
                    Id = v.Id,
                    Definition = new MetricDefinitionShortDto
                    {
                        Code = v.Definition != null ? v.Definition.Code : string.Empty,
                        Name = v.Definition != null ? v.Definition.Name : string.Empty
                    },
                    Value = v.Value ?? 0,
                    Unit = v.Definition != null ? v.Definition.Unit : string.Empty,
                    CreatedAt = v.Createdat ?? DateTime.MinValue
                })
                .ToListAsync();

            return new GetMetricValuesByReportResponse
            {
                ReportId = reportId,
                Values = values
            };
        }

        public async Task<CalculateMetricsResponse> CalculateMetricsAsync(CalculateMetricsRequest request)
        {
            var calculated = new List<CalculatedMetricDto>();
            var failed = new List<string>();

            // Mock implementation: Retrieve matching definitions and return mock values
            var definitions = await _dbContext.RatioDefinitions
                .Where(d => request.MetricCodes.Contains(d.Code))
                .ToListAsync();

            foreach (var code in request.MetricCodes)
            {
                var def = definitions.FirstOrDefault(d => d.Code == code);
                if (def != null)
                {
                    var mockValue = new Random().Next((int)10m, (int)50m) + (decimal)new Random().NextDouble();
                    calculated.Add(new CalculatedMetricDto
                    {
                        Code = def.Code ?? string.Empty,
                        Value = Math.Round(mockValue, 2),
                        Unit = def.Unit ?? string.Empty
                    });
                }
                else
                {
                    failed.Add(code);
                }
            }

            return new CalculateMetricsResponse
            {
                ReportId = request.ReportId,
                Calculated = calculated,
                Failed = failed
            };
        }
    }
}
