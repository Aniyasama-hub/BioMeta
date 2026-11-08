source("app/R/toolbox.R", encoding="UTF-8")
source("app/R/workbench_settings.R", encoding="UTF-8")
source("app/R/bulk_workflow.R", encoding="UTF-8")
source("app/R/plots.R", encoding="UTF-8")
source("app/R/toolbox_analysis.R", encoding="UTF-8")
nodes <- tb_flow_nodes_from_tools(c("pca", "deg", "pca", "figure_layout"))
stopifnot(identical(vapply(nodes, `[[`, "", "id"), c("pca", "deg", "pca_2", "figure_layout")))
tb_flow_validate(nodes, tb_tool_catalog()$id)
stopifnot(inherits(try(tb_flow_validate(tb_flow_nodes_from_tools(c("figure_layout","pca")), tb_tool_catalog()$id), silent=TRUE),"try-error"))
local({
 root <- tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE))
 tb_save_settings(root,list(workflow_preset=nodes))
 stopifnot(identical(tb_read_settings(root)$workflow_preset,nodes))
})
stopifnot(identical(.pathway_display_label(c("[BP] [CC] Cell cycle", "[recatome] Metabolism")), c("Cell cycle","Metabolism")))
raw <- data.frame(Ensembl=c("ENSG1","ENSG2"),Symbol=c("A","B"), log2FC=c(1,-2),padj=c(.01,.02))
mapped <- tb_resolve_gene_columns(raw,list(gene_id_column="Ensembl",gene_name_column="Symbol"))
stopifnot(identical(mapped$gene_id,raw$Ensembl),identical(mapped$gene_name,raw$Symbol))
raw$Ensembl[2]<-raw$Ensembl[1]
stopifnot(inherits(try(tb_resolve_gene_columns(raw,list(gene_id_column="Ensembl",gene_name_column="Symbol")),silent=TRUE),"try-error"))
stopifnot(identical(tb_panel_fields(1),"panel_01"))
cat("PASS flow instances, plan persistence, invalid layouts, clean labels, explicit mapping, duplicate-ID rejection and one-panel layout\n")

# Repeated tool instances retain their own source and parameters.
flow <- list(step=2L,nodes=tb_flow_nodes_from_tools(c("pca","pca")),params=list(group_mode="pair"),
  inputs=list(counts="first.csv"),stage_inputs=list(pca_2=list(counts="second.csv")),
  stage_params=list(pca_2=list(pca_top=77)),approved=list())
request <- tb_bulk_spec(flow,"pca",tb_default_settings(getwd()))
stopifnot(identical(request$inputs$counts,"second.csv"),request$params$pca_top==77)
source("app/R/public_pathways.R",encoding="UTF-8")
if (requireNamespace("org.Hs.eg.db",quietly=TRUE)) {
 db <- getExportedValue("org.Hs.eg.db","org.Hs.eg.db")
 ids <- head(AnnotationDbi::keys(db,keytype="ENTREZID"),3)
 names <- unname(AnnotationDbi::mapIds(db,ids,"SYMBOL","ENTREZID",multiVals="asNA"))
 genes <- data.frame(gene_id=ids,gene_name=names)
 stopifnot(identical(tb_entrez_ids(genes,db),ids))
 bad <- genes[1,,drop=FALSE];bad$gene_name <- names[2]
 stopifnot(inherits(try(tb_entrez_ids(bad,db),silent=TRUE),"try-error"))
 local({
   temp <- tempfile("mapping-audit-");dir.create(temp);dir.create(file.path(temp,"outputs"))
   on.exit(unlink(temp,recursive=TRUE))
   engine <- list(require_packages=function(x) invisible(NULL),
     write_manifest=function(data,path) jsonlite::write_json(data,path,auto_unbox=TRUE,pretty=TRUE),
     write_table=function(data,path) utils::write.csv(data,path,row.names=FALSE))
   spec <- list(tool="go",params=list(pathway_source="go",species="human",go_ontology="BP"))
   cfg <- tb_public_pathways(list(pathways=list()),spec,genes,getwd(),temp,engine)
   report <- read.csv(file.path(temp,"outputs/public_gene_mapping.csv"),colClasses="character")
   stopifnot(nrow(report)==3L,all(report$status=="mapped"),all(report$gene_id==ids),file.exists(cfg$pathways$gmt))
 })
}
cat("PASS per-instance inputs and actual human annotation mapping/conflict/audit report\n")

# Per-stage annotation choices must survive returning to the stage.
flow <- list(step=1L,nodes=tb_flow_nodes_from_tools("go"),params=list(group_mode="pair"),
  inputs=list(counts=""),synthetic=TRUE,custom=FALSE,terms=list(go=""),approved=list(),
  stage_params=list(go=list(pathway_source="go",pathway_terms="GO:0006955")))
request <- tb_bulk_spec(flow,"go",tb_default_settings(getwd()))
stopifnot(request$params$pathway_source=="go",request$params$pathway_terms=="GO:0006955")
cat("PASS per-stage annotation source and term restoration\n")
