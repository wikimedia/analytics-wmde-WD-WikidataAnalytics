#!/usr/bin/env Rscript

### ---------------------------------------------------------------------------
### --- WD_percentUsage_PRODUCTION.R, v 0.0.1
### --- script: WD_percentUsage_PRODUCTION.R
### --- Author: Goran S. Milovanovic, Data Scientist, WMDE
### --- Developed under the contract between Goran Milovanovic PR Data Kolektiv
### --- and WMDE.
### --- Contact: goran.milovanovic_ext@wikimedia.de
### --- July 2020.
### ---------------------------------------------------------------------------
### --- DESCRIPTION:
### --- Datasets Production for the Wikidata Usage and Coverage (WDUC) Project
### ---------------------------------------------------------------------------
### ---------------------------------------------------------------------------
### --- LICENSE:
### ---------------------------------------------------------------------------
### --- GPL v2
### --- This file is part of Wikidata Usage and Coverage (WDUC)
### ---
### --- WDUC is free software: you can redistribute it and/or modify
### --- it under the terms of the GNU General Public License as published by
### --- the Free Software Foundation, either version 2 of the License, or
### --- (at your option) any later version.
### ---
### --- WDUC is distributed in the hope that it will be useful,
### --- but WITHOUT ANY WARRANTY; without even the implied warranty of
### --- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### --- GNU General Public License for more details.
### ---
### --- You should have received a copy of the GNU General Public License
### --- along with WDUC. If not, see <http://www.gnu.org/licenses/>.

# - toReport
print(paste0("Initiate on: ", Sys.time()))

### --- Setup
library(XML)
library(data.table)
library(dplyr)

### --- Read paramereters
# - fPath: where the scripts is run from?
fPath <- as.character(commandArgs(trailingOnly = FALSE)[4])
fPath <- gsub("--file=", "", fPath, fixed = T)
fPath <- unlist(strsplit(fPath, split = "/", fixed = T))
fPath <- paste(
  paste(fPath[1:length(fPath) - 1], collapse = "/"),
  "/",
  sep = "")
params <- xmlParse(paste0(fPath, "wd_percentUsage_Config.xml"))
params <- xmlToList(params)
dataDir <- params$general$dataDir
analyticsDir <- params$general$analyticsDir
hdfsPath <- params$general$hdfsPath
publicDir <- params$general$publicDir
logDir <- params$general$logDir


# - spark2-submit parameters:
paramsDeploy <- xmlParse(paste0(fPath, "wd_percentUsage_Config_Deployment.xml"))
paramsDeploy <- xmlToList(paramsDeploy)
sparkMaster <- paramsDeploy$spark$master
sparkDeployMode <- paramsDeploy$spark$deploy_mode
sparkNumExecutors <- paramsDeploy$spark$num_executors
sparkDriverMemory <- paramsDeploy$spark$driver_memory
sparkExecutorMemory <- paramsDeploy$spark$executor_memory
sparkExecutorCores <- paramsDeploy$spark$executor_cores
sparkConfigDynamic <- paramsDeploy$spark$config

### --- Functions
# - projectType() to determine project type
projectType <- function(projectName) {
  unname(sapply(projectName, function(x) {
    if (grepl("commons", x, fixed = T)) {"Commons"
    } else if (grepl("mediawiki|meta|species|wikidata", x)) {"Other"
    } else if (grepl("wiki$", x)) {"Wikipedia"
    } else if (grepl("quote$", x)) {"Wikiquote"
    } else if (grepl("voyage$", x)) {"Wikivoyage"
    } else if (grepl("news$", x)) {"Wikinews"
    } else if (grepl("source$", x)) {"Wikisource"
    } else if (grepl("wiktionary$", x)) {"Wiktionary"
    } else if (grepl("versity$", x)) {"Wikiversity"
    } else if (grepl("books$", x)) {"Wikibooks"
    } else {"Other"}
  }))
}

# - toReport
print("Fetch usage data from goransm.wdcm_clients_wb_entity_usage: PySpark")

### ---------------------------------------------------------------------------
### --- 1: Run Pyspark ETL
### ---------------------------------------------------------------------------

# - toRuntime Log:
print("Log: RUN WD_percentUsage_ETL.py")

# - clean dataDir
if (length(list.files(dataDir)) > 1) {
  file.remove(paste0(dataDir, list.files(dataDir)))
}
# - Kerberos init
system(command = 'sudo -u analytics-privatedata kerberos-run-command analytics-privatedata hdfs dfs -ls', 
       wait = T)
# - Run PySpark ETL
system(command = paste0('sudo -u analytics-privatedata spark2-submit ', 
                        sparkMaster, ' ',
                        sparkDeployMode, ' ', 
#                        sparkNumExecutors, ' ',
                        sparkDriverMemory, ' ',
                        sparkExecutorMemory, ' ',
                        sparkExecutorCores, ' ',
                        '--conf spark.dynamicAllocation.maxExecutors=100 --conf spark.executor.extraJavaOptions=-Dlog4j.configuration=/etc/spark2/defaults/log4j.properties --conf spark.driver.extraJavaOptions=-Dlog4j.configuration=/etc/spark2/defaults/log4j.properties ',
                        paste0(fPath, 'WD_percentUsage_ETL.py')
),
wait = T)

# - toRuntime Log:
print("Log: RUN WD_percentUsage_ETL.py COMPLETED.")

### ---------------------------------------------------------------------------
### --- 2: Compose Usage and Coverage Datasets
### ---------------------------------------------------------------------------

### --- datasets: wdUsage
# - copy splits from hdfs to local dataDir
system(paste0('sudo -u analytics-privatedata kerberos-run-command analytics-privatedata hdfs dfs -ls ', 
              hdfsPath, 'wdUsage > ', 
              dataDir, 'files.txt'), 
       wait = T)
files <- read.table(paste0(dataDir, 'files.txt'), skip = 1)
files <- as.character(files$V8)[2:length(as.character(files$V8))]
file.remove(paste0(dataDir, 'files.txt'))
for (i in 1:length(files)) {
  system(paste0('sudo -u analytics-privatedata kerberos-run-command analytics-privatedata hdfs dfs -text ', 
                files[i], ' > ',  
                paste0(dataDir, "wdUsage", i, ".csv")), wait = T)
}
# - read splits: dataSet
# - load
lF <- list.files(dataDir)
lF <- lF[grepl("wdUsage", lF)]
wdUsage <- lapply(paste0(dataDir, lF), function(x) {fread(x,
                                                          header = F,
                                                          sep = ",")})
# - collect
wdUsage <- rbindlist(wdUsage)
# - schema
colnames(wdUsage) <- c('eu_page_id', 'wiki_db')
# - set key: wiki_db
setkey(wdUsage, wiki_db)

### --- datasets: wdSitelinks
# - copy splits from hdfs to local dataDir
system(paste0('sudo -u analytics-privatedata kerberos-run-command analytics-privatedata hdfs dfs -ls ', 
              hdfsPath, 'wdSitelinks > ', 
              dataDir, 'files.txt'), 
       wait = T)
files <- read.table(paste0(dataDir, 'files.txt'), skip = 1)
files <- as.character(files$V8)[2:length(as.character(files$V8))]
file.remove(paste0(dataDir, 'files.txt'))
for (i in 1:length(files)) {
  system(paste0('sudo -u analytics-privatedata kerberos-run-command analytics-privatedata hdfs dfs -text ', 
                files[i], ' > ',  
                paste0(dataDir, "wdSitelinks", i, ".csv")), wait = T)
}
# - read splits: dataSet
# - load
lF <- list.files(dataDir)
lF <- lF[grepl("wdSitelinks", lF)]
wdSitelinks <- lapply(paste0(dataDir, lF), function(x) {fread(x,
                                                              header = F,
                                                              sep = ",")})
# - collect
wdSitelinks <- rbindlist(wdSitelinks)
# - schema
colnames(wdSitelinks) <- c('eu_page_id', 'wiki_db')
# - set key: wiki_db
setkey(wdSitelinks, wiki_db)

# - toReport
print("READY: usage data from goransm.wdcm_clients_wb_entity_usage: PySpark.")

### ---------------------------------------------------------------------------
### --- 3: Iterate across page tables per project, fetch namespace 0 pages
### ---------------------------------------------------------------------------

# - projects tracked
projectsTracking <- sort(unique(wdSitelinks$wiki_db))

# - toReport
print("SQL iterate across clients, fetch data, and produce the dataset.")

# - iterate
projectStats <- list()
tStart <- Sys.time()
c <- 0
for (i in 1:length(projectsTracking)) {
  pages <- tryCatch(
    {
      mySqlArgs <- 
        paste0('/usr/local/bin/analytics-mysql ', projectsTracking[i], ' ') 
      mySqlInput <- paste0('"SELECT page_id FROM page WHERE (page_namespace = 0 AND page_is_redirect != 1);" > ',
                           dataDir, 'currentProject.tsv')
      # - command:
      mySqlCommand <- paste0(mySqlArgs, " -e ", mySqlInput, collapse = "")
      print(paste0("Running the following query: ", mySqlCommand))
      system(command = mySqlCommand, wait = TRUE)
      fread(paste0(dataDir, 'currentProject.tsv'), sep = "\t", quote = "")
    },
    error = function(condition) {
      return(paste0("Error in /usr/local/bin/analytics-mysql ", projectsTracking[i]))
    },
    warning = function(condition) {
      return(paste0("Error in /usr/local/bin/analytics-mysql ", projectsTracking[i]))
    }
  )
  if (sum(class(pages) == "character") == 0) {
    numPages <- length(unique(pages$page_id))
    localProject <- wdUsage %>%
      filter(wiki_db %in% projectsTracking[i])
    localProjectSitelinks <- wdSitelinks %>%
      filter(wiki_db %in% projectsTracking[i])
    if (dim(localProjectSitelinks)[1] > 0) {
      c <- c + 1
      wdUsePages <- length(which(unique(pages$page_id) %in% localProject$eu_page_id))
      wdSitelinksPages <- length(which(unique(pages$page_id) %in% localProjectSitelinks$eu_page_id))
      projectStats[[c]] <- data.frame(project = projectsTracking[i], 
                                      numPages = numPages,
                                      wdUsePages = wdUsePages,
                                      wdSitelinksPages = wdSitelinksPages,
                                      percentWDuse = round(wdUsePages/numPages*100, 2),
                                      percentWDsitelinks = round(wdSitelinksPages/numPages*100, 2),
                                      stringsAsFactors = F)
      # - toReport
      print("-------------------------------------------------------------------------------")
      print(paste0("Scanned project ", i, " out of: ", length(projectsTracking)))
      print(paste0("Project ", projectStats[[c]]$project, 
                   " has ", projectStats[[c]]$numPages, " pages, of which ", 
                   projectStats[[c]]$wdUsePages, " make use of WD, excluding Sitelinks."))
      print(paste0("Project ", projectStats[[c]]$project, 
                   " has ", projectStats[[c]]$numPages, " pages, of which ", 
                   projectStats[[c]]$percentWDuse, "% make use of WD, excluding Sitelinks."))
      print(paste0("Project ", projectStats[[c]]$project, 
                   " has ", projectStats[[c]]$numPages, " pages, of which ", 
                   projectStats[[c]]$wdSitelinksPages, " % make use of Sitelinks."))
      print(paste0("Project ", projectStats[[c]]$project, 
                   " has ", projectStats[[c]]$numPages, " pages, of which ", 
                   projectStats[[c]]$percentWDsitelinks, " % make use of Sitelinks."))
      print(paste0("Collected ", c, " projects out of ", length(projectsTracking), " so far. NEXT."))
    }
  } else {
    print(pages)
  }
  Sys.sleep(2)
}
# - bind
projectStats <- rbindlist(projectStats)
# - remove projects with no data:
w <- which(projectStats$wdUsePages + projectStats$wdSitelinksPages == 0)
if (length(w) > 0) {
  projectStats <- projectStats[-w, ]
}

# - toReport
print(paste0("Fetch and Compare took: ", tEnd <- Sys.time() - tStart, " total time."))

# - add projectType
projectStats$projectType <- projectType(projectStats$project)
# - store
write.csv(projectStats, 
          paste0(analyticsDir, "wdUsage_ProjectStatistics.csv"))

### ---------------------------------------------------------------------------
### --- 4: Publish results and Log
### ---------------------------------------------------------------------------

# - clean up
file.remove(paste0(dataDir, list.files(dataDir)))

### --- publish results:
# - toReport
print("Copy to production.")
# - migrate to /srv/published-datasets
system(command = paste0('cp ', analyticsDir, 'wdUsage_ProjectStatistics.csv ', publicDir), 
       wait = T)
# - toReport
print(paste0("DONE: ", Sys.time()))

### --- copy and clean up log files:
# - conclusion
print("DONE. Exiting.")
# - copy the main log file to published for timestamp
# - archive:
lF <- list.files(fPath)
lF <- lF[grepl('\\.log$', lF)]
lapply(lF, function(x) {
  system(command = 
           paste0('cp ', fPath, x, ' ', logDir),
         wait = T)
})
# - clean up
file.remove(paste0(fPath, lF))






