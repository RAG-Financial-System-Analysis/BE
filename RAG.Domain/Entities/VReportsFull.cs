using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class VReportsFull
{
    public Guid? Id { get; set; }

    public int? Year { get; set; }

    public string? Period { get; set; }

    public string? Fileurl { get; set; }

    public string? Filename { get; set; }

    public string? Visibility { get; set; }

    public DateTime? Createdat { get; set; }

    public string? Ticker { get; set; }

    public string? Companyname { get; set; }

    public string? Categoryname { get; set; }

    public string? Uploadedbyname { get; set; }

    public Guid? Uploadedbyid { get; set; }

    public long? Ratiocount { get; set; }
}
