using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.Enum;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [ApiController]
    [Route("api/jobs")]
    [Authorize(Roles = SystemRoles.Admin + "," + SystemRoles.Analyst)]
    public class JobsController : ControllerBase
    {
        private readonly IJobService _jobService;

        public JobsController(IJobService jobService)
        {
            _jobService = jobService;
        }

        /// <summary>
        /// Get job status and result
        /// </summary>
        /// <param name="jobId">Job ID returned from async upload or chat</param>
        /// <returns>Job status with progress and result (if completed)</returns>
        [HttpGet("{jobId}/status")]
        public async Task<IActionResult> GetJobStatus(Guid jobId)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid userId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var jobStatus = await _jobService.GetJobStatusAsync(jobId);
                
                // Verify job belongs to user (security check)
                var jobData = await _jobService.GetJobDataAsync(jobId);
                if (jobData?.UserId != userId)
                {
                    return Forbid("You don't have access to this job.");
                }

                return Ok(jobStatus);
            }
            catch (FileNotFoundException)
            {
                return NotFound(new { Message = "Job not found" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { 
                    Message = "An error occurred while getting job status.", 
                    Details = ex.Message 
                });
            }
        }

        /// <summary>
        /// Get job result (alias for status when completed)
        /// </summary>
        /// <param name="jobId">Job ID</param>
        /// <returns>Job result if completed</returns>
        [HttpGet("{jobId}/result")]
        public async Task<IActionResult> GetJobResult(Guid jobId)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid userId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var jobStatus = await _jobService.GetJobStatusAsync(jobId);
                
                // Verify job belongs to user
                var jobData = await _jobService.GetJobDataAsync(jobId);
                if (jobData?.UserId != userId)
                {
                    return Forbid("You don't have access to this job.");
                }

                if (jobStatus.Status != "completed")
                {
                    return BadRequest(new { 
                        Message = $"Job is not completed yet. Current status: {jobStatus.Status}",
                        Progress = jobStatus.Progress
                    });
                }

                return Ok(new {
                    JobId = jobId,
                    Status = jobStatus.Status,
                    Result = jobStatus.Result
                });
            }
            catch (FileNotFoundException)
            {
                return NotFound(new { Message = "Job not found" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { 
                    Message = "An error occurred while getting job result.", 
                    Details = ex.Message 
                });
            }
        }
    }
}