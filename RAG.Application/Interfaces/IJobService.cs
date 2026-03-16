using RAG.Domain.DTOs.Job;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IJobService
    {
        Task<Guid> CreateJobAsync(string jobType, Guid userId, object inputData);
        Task<JobStatusResponse> GetJobStatusAsync(Guid jobId);
        Task UpdateJobStatusAsync(Guid jobId, string status, int progress, string? errorMessage = null);
        Task CompleteJobAsync(Guid jobId, object result);
        Task<JobData?> GetJobDataAsync(Guid jobId);
        
        // Timeout handling methods
        Task<bool> IsJobTimedOutAsync(Guid jobId, int timeoutMinutes = 30);
        Task MarkJobAsTimedOutAsync(Guid jobId);
        Task<List<Guid>> GetTimedOutJobsAsync(int timeoutMinutes = 30);
    }
}