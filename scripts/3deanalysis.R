#***********************************************************
#*************************RNA SEQ **************************
#***********************************************************

#---------------------LOADING PARMS----------------------
library(this.path)
library(stringr)
#Choose primary workflow file path
file.dir<-this.dir()
file.path<-str_replace(file.dir,"scripts","")

#Load user-set parms file
parms<-read.delim(paste(file.path,"parms.txt",sep=""),sep=":")

#Redefine parms for R
paired.end.status<-as.logical(trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="paired.end.status"),2]))
ref.genome<-trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="ref.genome"),2])
use.existing.counts<-as.logical(trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="use.existing.counts"),2]))
interest.group<-trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="interest.group"),2])
thresh.value<-as.numeric(trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="thresh.value"),2]))
sample.value<-as.numeric(trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="sample.value"),2]))
feature.type<-trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="feature.type"),2])
attribute.type<-trimws(parms[which(parms$RNA_SEQ_PARAMETERS=="attribute.type"),2])

#Load design matrix
design<-read.csv(paste(file.path,"design.csv",sep=""))
names(design)[1]<-gsub("�..","",names(design)[1])

#Load packages
library(BiocManager)
library(Rsubread)
library(stringr)
library(edgeR)
library(limma)
library(Glimma)
library(gplots)
library(RColorBrewer)
set.seed(42)

#Create text file to update user
update<-data.frame(Update="Status")

#Remove existing progress files
progress.files<-list.files(path=paste(file.path,"progress",sep=""),full.names = TRUE)
file.remove(progress.files)

#---------------COUNTING FEATURES----------------------

setwd(paste(file.path,"progress",sep=""))
write.table(update,"COUNTING FEATURES.txt")

#Get aligned .bam files in 1fastqfiles
bam.files <- list.files(path = paste(file.path,"1fastqfiles/",sep=""), 
                        pattern = ".BAM$", 
                        full.names = TRUE)

if(use.existing.counts==FALSE){
  
  if(ref.genome=="mm9"||ref.genome=="mm10"||ref.genome=="hg19"||ref.genome=="hg38"){
    #Count features (count RNA reads in .bam files)
    fc <- featureCounts(files=bam.files, 
                        annot.inbuilt=ref.genome,
                        isPairedEnd=paired.end.status)
  } else{
    annot.file<-list.files(path=paste(file.path,"3annotations/",sep=""),
                           pattern=paste("^",ref.genome,sep=""),
                           full.names = TRUE)
    
    fc <- featureCounts(files=bam.files, 
                        annot.ext=annot.file,
                        isPairedEnd=paired.end.status,
                        isGTFAnnotationFile=TRUE,
                        GTF.featureType = feature.type,
                        GTF.attrType= attribute.type)
  }
  
  countdata<-as.data.frame(fc$counts)
  names(countdata)<-str_replace_all(names(countdata),".fastq.gz.subread.BAM","")
  
  setwd(paste(file.path,"1fastqfiles",sep=""))
  write.csv(countdata,"rawfeaturecounts.csv",row.names=TRUE)
} else{
  countdata<-as.data.frame(read.csv(paste(file.path,"/1fastqfiles/rawfeaturecounts.csv",sep="")))
  rownames(countdata)<-countdata$X
  countdata<-countdata[,-1]
}

#---------------REMOVE LOWLY EXPRESSED GENES----------------------

setwd(paste(file.path,"progress",sep=""))
write.table(update,"REMOVING POORLY EXPRESSED GENES.txt")

#Calculate CPM (counts per million)
myCPM<-cpm(countdata)
#Select genes with high CPM
thresh <- myCPM > thresh.value
keep <- rowSums(thresh) >= sample.value
counts.keep<-countdata[keep,]

for(i in 1:length(names(countdata))){
  #Plot CPM v.s. Counts, check that count of 10 approximates thresh.value
  setwd(paste(file.path,"plots/Quality",sep=""))
  png(paste("CPM",i,".png",sep=""))
  plot(myCPM[,i],countdata[,i],
       ylim=c(0,50),xlim=c(0,10),
       ylab = paste(names(countdata)[i]," Raw Counts",sep=""),xlab=paste(names(countdata)[i]," CPM",sep=""))
  abline(v=thresh.value)
  abline(h=10,lty="dashed",col="grey")
  dev.off()
}

#---------------------QUALITY CHECK----------------------

setwd(paste(file.path,"progress",sep=""))
write.table(update,"QUALITY CHECKING COUNTS.txt")

#Convert counts to DGEobject
dgeObj <- DGEList(counts.keep)

#Generate color scheme from group
col.num<-grep(interest.group,names(design))
interest.col<-data.frame(Group=design[,col.num])
interest.levels<-levels(factor(interest.col$Group))
interest.col$Col<-ifelse(interest.col$Group==interest.levels[1],"purple","orange")
color.select<-interest.col$Col

#Plot library sizes to check consistency
setwd(paste(file.path,"plots/Quality",sep=""))
png("LibraryBarPlot.png")
barplot(dgeObj$samples$lib.size, 
        names=colnames(dgeObj),
        las=2)
title("Barplot of library sizes")
dev.off()

#Calculate log2 of counts
logcounts <- cpm(dgeObj,log=TRUE)
#Plot distribution to ensure normally distributed
setwd(paste(file.path,"plots/Quality",sep=""))
png("Logcounts.png")
boxplot(logcounts, 
        xlab="", 
        ylab="Log2 counts per million",
        las=2)
abline(h=median(logcounts),col="blue")
title("Boxplots of logCPMs (unnormalised)")
dev.off()

#Plot MDS (multidimensional scaling plot)
setwd(paste(file.path,"plots/Quality",sep=""))
png("MDSplot.png")
plotMDS(dgeObj,col=color.select)
title("MDS Plot")
dev.off()

#Estimate variance in each row of logcount2 matrix
var_genes <- apply(logcounts, 1, var)
#Get top 100 most variable genes
select_var <- names(sort(var_genes, decreasing=TRUE))[1:100]
select_var<-select_var[!is.na(select_var)]
#Get logcounts for most variable genes
highly_variable_lcpm<-logcounts[select_var,]

#Save most variable genes
setwd(paste(file.path,"plots/Quality",sep=""))
write.csv(highly_variable_lcpm,"highly_variable_genes_logcpm.csv",row.names = TRUE)

#Plot heatmap
mypalette <- brewer.pal(11,"RdYlBu")
morecols <- colorRampPalette(mypalette)
setwd(paste(file.path,"plots/Quality",sep=""))
png(file="High_var_genes.heatmap.png")
heatmap.2(highly_variable_lcpm,
          col=rev(morecols(50)),
          trace="none", 
          main="Top 100 most variable genes\nacross samples (if n>=100)",
          ColSideColors=color.select,
          scale="row",
          margins=c(10,10))
dev.off()

#---------------------DE ANALYSIS----------------------

setwd(paste(file.path,"progress",sep=""))
write.table(update,"COMMENCING DE ANALYSIS.txt")

#Normalize counts to correct for sampling bias (natural diff b/w samples)
dgeObj <- calcNormFactors(dgeObj)

#Estimate mean dispersion across all samples
dgeObj <- estimateCommonDisp(dgeObj)
#Estimate trended dispersion (mean dispersion across similar abundance genes)
dgeObj <- estimateGLMTrendedDisp(dgeObj)
#Estimate tagwise dispersion
dgeObj <- estimateTagwiseDisp(dgeObj)

#***THEORY OF GENERAL LINEAR MODEL (GLM)***
#*
#Plot group on x axis by gene expression on y axis
#Use linear regression to describe gene expression in each group
#Turns out that least squares fit is just the mean of each group

#Linear Model: y=N*mean(control)+M*mean(mutant)
#Where N and M are either 0 or 1
#When N=1 & M=0, models control gene expression (within group)
#When N=0 & M=1, models mutant gene expression (within group)
#Var(control)+Var(mutant)=Var(total)=Var(between group)

#OR Linear Model: y=N*mean(control)+M*mean(mutant-control)
#Where N=1 and M is either 0 or 1
#When N=1 & M=0, models control gene expression (within group)
#When N=1 & M=1, models mutant gene expression (within group)
#Var(control)+Var(mutant)=Var(total)=Var(between group)
#^THIS IS THE ONE EDGER USES TO FORMAT DESIGN MATRIX

#F = Var(between group)/Mean(Var(within groups))
#Can use F distribution to determine significance

#***END GLM THEORY***

#Fit linear model to model relationship b/w gene and phenotype
#Assumes no interaction between variables
fit <- glmFit(dgeObj, design)

#Use general model to identify fold changes & FDR
#FDR stands for false discovery rate (corrected p value)
design.col.num<-grep(interest.group,names(design))
lrt <- glmLRT(fit, coef=design.col.num) 

#Get output
output<-as.data.frame(topTags(lrt,n=Inf))

#Reformat output
output$GeneID<-rownames(output)
output<-output[,c(6,1,2,3,4,5)]

#Save non-annotated version
setwd(paste(file.path,"plots/",sep=""))
write.csv(output,"not_annotated_output.csv",row.names=FALSE)

#Create volcano plot
#FDR<0.05 is used as significance threshold
setwd(paste(file.path,"plots/",sep=""))
png(file="volcanoplot.png")
plot(x=output$logFC,
     y=-log10(output$FDR),
     pch=16)
#Layers significant points in red on top
points(x=output$logFC,
       y=-log10(output$FDR),
       pch=16,
       col=ifelse(output$FDR<0.05,"red","black"))
abline(h=-log10(0.05))
dev.off()

#Annotate output
if(ref.genome=="mm10"||ref.genome=="mm9"){
  library(org.Mm.eg.db)
  ann <- select(org.Mm.eg.db,
                keys=output$GeneID,
                columns=c("ENTREZID","SYMBOL","GENENAME"))
} else if(ref.genome=="hg19"||ref.genome=="hg38"){
  library(org.Hs.eg.db)
  ann <- select(org.Hs.eg.db,
                keys=output$GeneID,
                columns=c("ENTREZID","SYMBOL","GENENAME"))
}

output.ann <- cbind(output, ann[,2:3])

#Rank genes by order of sig
output.ord<-output.ann[order(output.ann$logFC),]

#Save output
setwd(paste(file.path,"plots/",sep=""))
write.csv(output.ord,"output.csv",row.names=FALSE)

#---------------------GSEA ANALYSIS----------------------

setwd(paste(file.path,"progress",sep=""))
write.table(update,"COMMENCING GSEA ANALYSIS.txt")

library(fgsea)
library(reactome.db)

#Format ranked output for fgsea
ranks<-output.ord$logFC
names(ranks) <- output.ord$GeneID

#Load gene pathways
pathways <- reactomePathways(names(ranks))

#Determine enriched gene pathways
fgseaRes <- fgsea(pathways, 
                  ranks, 
                  minSize=15, 
                  maxSize = 500)

#Save top enriched pathways
setwd(paste(file.path,"plots/",sep=""))
png("EnrichedPathways.png")
topPathwaysUp <- fgseaRes[ES > 0][head(order(pval), n=15), pathway]
topPathwaysDown <- fgseaRes[ES < 0][head(order(pval), n=15), pathway]
topPathways <- c(topPathwaysUp, rev(topPathwaysDown))
plotGseaTable(pathways[topPathways], 
              ranks, 
              fgseaRes, 
              gseaParam = 0.5,
              colwidths = c(6.2, 3, 0.8, 0, 1.2))
dev.off()

#Save top pathways with corresponding genes
mylist<-pathways[topPathways]
setwd(paste(file.path,"plots/",sep=""))
capture.output(mylist,file="enrichedpathwaygenes.txt")

setwd(paste(file.path,"progress",sep=""))
write.table(update,"ANALYSIS COMPLETE.txt")
write.table(interest.col,"ColorSchemeReference.txt")