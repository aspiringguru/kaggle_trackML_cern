#from https://www.kaggle.com/sionek/mod-dbscan-x-100-parallel

#run once only
install.packages("data.table", dependencies=TRUE)


require(data.table)
require(bit64)

#run once only
install.packages("dbscan", dependencies=TRUE)
require(dbscan)

install.packages("doParallel", dependencies=TRUE)
require(doParallel)

setwd('/home/ubuntu/kaggleData/train_1')


score<-function(sub,dft){
  df=merge(sub,dft[,.(hit_id,particle_id,weight)])
  df[,Np:=.N,by=particle_id]# Np = Hits per Particle
  df[,Nt:=.N,by=track_id]   # Nt = Hits per Track
  df[,Ntp:=.N,by=list(track_id,particle_id)]# Hits per Particle per Track
  df[,r1:=Ntp/Nt]
  df[,r2:=Ntp/Np]
  sum(df[r1>.5 & r2>.5,weight])
}

########################
### working function ###
########################
trackML <- function(dfh){
  dfh[,r:=sqrt(x*x+y*y+z*z)]
  dfh[,rt:=sqrt(x*x+y*y)]
  dfh[,a0:=atan2(y,x)]
  dfh[,z1:=z/rt]
  dfh[,z2:=z/r]
  dz0    <- -0.00070
  stepdz <-  0.00001
  stepeps<-  0.000005
  mm     <-  1
  for (ii in 0:100) {
    mm <- mm*(-1)
    dz <- mm*(dz0 + ii*stepdz)
    dfh[,a1:=a0+dz*z*sign(z)]
    dfh[,sina1:=sin(a1)]
    dfh[,cosa1:=cos(a1)]
    dfs=scale(dfh[,.(sina1,cosa1,z1,z2)])
    cx <- c(1, 1, 0.4, 0.4)
    for (jj in 1:ncol(dfs)) dfs[,jj] <- dfs[,jj]*cx[jj]
    res=dbscan(dfs,eps=0.0035+ii*stepeps,minPts = 1)
    if (ii==0) {
      dfh[,s1:=res$cluster]
      dfh[,N1:=.N, by=s1]
    }else{
      dfh[,s2:=res$cluster]
      dfh[,N2:=.N, by=s2]
      maxs1 <- max(dfh$s1)
      dfh[,s1:=ifelse(N2>N1 & N2<20,s2+maxs1,s1)]
      dfh[,s1:=as.integer(as.factor(s1))]
      dfh[,N1:=.N, by=s1]
    }
  }
  return(dfh$s1)
}

########################
###    evaluation    ###
########################
print("Evaluation (sequential)")
path <- '/home/ubuntu/kaggleData/train_1/'
sc=1:3 # 1:100
for(i in 0:2){ # 0:99
  dfh=fread(paste0(path,'event00000100',i,'-hits.csv'))
  dft=fread(paste0(path,'event00000100',i,'-truth.csv'),stringsAsFactors = T)
  dfh$s1 <- trackML(dfh)
  sub=data.table(event_id=nev,hit_id=dfh$hit_id,track_id=dfh$s1)
  s=score(sub,dft)
  print(c(i,s))
  sc[i+1]=s
}
print(mean(sc))

########################
###    submission    ###
########################
namef <- system("cd /home/ubuntu/kaggleData/test; ls *hits.csv", intern=TRUE)
path <- '/home/ubuntu/kaggleData/test/'
print("Preparing submission")

### sequential ###
# print("Sequential")
# for(nev in 0:124){
#   print(nev)
#   dfh <- fread(paste0(path,namef[nev+1]))
#   dfh$s1 <- trackML(dfh)
#   subN <- data.table(event_id=nev,hit_id=dfh$hit_id,track_id=dfh$s1)
#   if (nev==0) {
#     sub <- subN
#   }else{
#     sub <- rbind(sub,subN)
#   }
# }
#################

### parallel ###
registerDoParallel(cores=4)
print("Parallel") # wait until "Finished"
# Start the clock!
ptm <- proc.time()
sub <- foreach(nev = 0:124, .combine = rbind)  %dopar%  {
         dfh <- fread(paste0(path,namef[nev+1]))
         dfh$s1 <- trackML(dfh)
         subEvent <- data.table(event_id=nev,hit_id=dfh$hit_id,track_id=dfh$s1)
         return(subEvent)
       }
# Stop the clock
proc.time() - ptm
#outputs time for user, system & elapsed

#set working dir to home, to avoid write errors.
#NB: rstudio runs as linux user logged in as.
setwd('~/')
fwrite(sub, "sub-100-DBSCAN.csv")
print('Finished')
#
