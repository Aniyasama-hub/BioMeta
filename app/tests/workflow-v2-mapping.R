# Synthetic custom-column DEG -> actual GO/GSEA-style ingestion; no count modelling.
root <- normalizePath("app", winslash="/")
source(file.path(root,"R/toolbox.R"),encoding="UTF-8")
source(file.path(root,"R/toolbox_analysis.R"),encoding="UTF-8")
local({
  temp <- tempfile("mapping-fixture-");dir.create(temp)
  on.exit(unlink(temp,recursive=TRUE))
  deg <- read.csv(file.path(root,"examples/demo_deg.csv"),check.names=FALSE)
  names(deg)[names(deg)=="gene_id"] <- "input_identifier"
  names(deg)[names(deg)=="gene_name"] <- "input_symbol"
  input <- file.path(temp,"aliases.csv");write.csv(deg,input,row.names=FALSE)
  spec <- list(tool="go",inputs=list(deg=input,gmt=file.path(root,"examples/demo_sets.gmt")),
    params=list(pathway_source="custom",gene_id_column="input_identifier",gene_name_column="input_symbol",
      gmt_id_type="gene_id",database_version="synthetic mapping check",group_mode="pair"),
    style=list(formats="png",width=5,height=4,dpi=96))
  job <- tb_launch_job(spec,root);job$process$wait()
  state <- tb_read_job(job$directory)
  if (state$status!="completed") stop(state$error %||% state$summary)
  mapped <- read.csv(file.path(job$directory,"outputs/input_gene_mapping.csv"))
  stopifnot(identical(mapped$gene_id,deg$input_identifier),identical(mapped$gene_name,deg$input_symbol))
  cat("PASS actual GO worker with selected ID/symbol columns and full mapping report\n")
})
