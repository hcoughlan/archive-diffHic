###################################################################################################
# This tests the interaction counting capabilities of, well, the interaction counter. 

Sys.setlocale(category="LC_COLLATE",locale="C")
chromos<-c(chrA=51, chrB=31)
source("simcounts.R")

binid <- function(curcuts, dist) {
	# Need to figure out which fragments belong in which bins.
	mids<-(start(curcuts)+end(curcuts))/2
	as.integer((mids-0.1)/dist)+1L
}

refnames<-c("count1", "count2", "anchor1", "anchor2")

# We set up the comparison function to check our results. 

finder <- function(dir1, dir2, dist, cuts, filter=10L, restrict=NULL, cap=NA) {
	overall <- list()
	odex <- 1L
	totals <- integer(2)
	collected <-c(0, cumsum(chromos))
	cap <- as.integer(cap)
    dirs <- c(dir1, dir2)

    xstats <- list()
    for (m in 1:2) {
        cur.dir <- dirs[m] 
        cur.x <- h5ls(cur.dir)
        cur.x <- cur.x[cur.x$otype=="H5I_DATASET",]
        xstats[[m]] <- data.frame(anchor1=basename(cur.x$group), anchor2=cur.x$name)
    }

	for (k in seq_along(chromos)) {
		cur.k <- names(chromos)[k]
		if (!is.null(restrict) && !cur.k %in% restrict) { next }
        current.krange <- cuts[cur.k==seqnames(cuts)]
        kbin <- binid(current.krange, dist)

		krle <- rle(kbin)
		kend <- cumsum(krle$length)
		kstart <- kend - krle$length + 1L

		for (l in seq_len(k)) {
			cur.l <- names(chromos)[l]
			if (!is.null(restrict) && !cur.l %in% restrict) { next }
			current.lrange <- cuts[seqnames(cuts)==cur.l]
			lbin <- binid(current.lrange, dist)

            max.anchor1 <- chromos[[k]]
			anti.a <- collected[k]
			max.anchor2 <- chromos[[l]]
			anti.t <- collected[l]

			# Loading counts.
			mats <- list()
			for (m in 1:2) {
                cur.dir <- dirs[m]
                cur.x <- xstats[[m]]
				if (any(cur.x$anchor1==cur.k & cur.x$anchor2==cur.l)) { 
					cur.pairs <- h5read(cur.dir, file.path(cur.k, cur.l))
				} else {
				    cur.pairs <- data.frame(anchor1.id=integer(0),anchor2.id=integer(0), count=integer(0))
				}

    			a <- cur.pairs[,1] - anti.a
                t <- cur.pairs[,2] - anti.t
                mat.dex <- (t - 1L) * max.anchor1 + a
                mat <- tabulate(mat.dex, nbins=max.anchor1*max.anchor2)
                dim(mat) <- c(max.anchor1, max.anchor2)

				if (!is.na(cap)) { 
					mat[mat > cap] <- cap 
					totes <- sum(mat)
				} else {
					totes <- nrow(cur.pairs)
				}
                mats[[m]] <- mat
				totals[m] <- totals[m] + totes
			}

			# Computing the region for each set of bins (assuming cuts are sorted).
			astart<-start(current.krange)[kstart]
			aend<-end(current.krange)[kend]
			lrle <- rle(lbin)
			lend <- cumsum(lrle$length)
			lstart <- lend - lrle$length + 1L
			tstart <- start(current.lrange)[lstart]
			tend <- end(current.lrange)[lend]
			
			# Computing the counts for each set of bins.
			counts1 <- split(mats[[1]], kbin)
			counts2 <- split(mats[[2]], kbin)
			current.counts <- list()
			current.anchor1 <- current.anchor2 <- list()
			idex <- 1L

			for (g in seq_along(counts1)) {
				subcounts1 <- split(matrix(counts1[[g]], nrow=max.anchor2, byrow=TRUE), lbin)
				subcounts2 <- split(matrix(counts2[[g]], nrow=max.anchor2, byrow=TRUE), lbin)
				for (i in seq_along(subcounts1)) {
					count.pair <- c(sum(subcounts1[[i]]), sum(subcounts2[[i]]))
					if (sum(count.pair)<filter) { next }

					current.counts[[idex]] <- count.pair
					current.anchor1[[idex]] <- c(astart[g], aend[g])
					current.anchor2[[idex]] <- c(tstart[i], tend[i])
					idex <- idex + 1L
				}
			}
		
			# Aggregating all data.
			if (length(current.counts)) {
				tempa<-do.call(rbind, current.anchor1)
				tempt<-do.call(rbind, current.anchor2)
				out<-data.frame(do.call(rbind, current.counts), paste0(cur.k, ":", tempa[,1], "-", tempa[,2]),
						paste0(cur.l, ":", tempt[,1], "-", tempt[,2]), stringsAsFactors=FALSE)
				overall[[odex]]<-out
				odex<-odex+1L
			}
		}
	}

	if (length(overall)) { 
		overall<-do.call(rbind, overall)
		overall<-overall[do.call(order, overall),]
		rownames(overall)<-NULL
	} else {
		overall<-data.frame(integer(0), integer(0), character(0), character(0), numeric(0), stringsAsFactors=FALSE)
	}
	colnames(overall)<-refnames
	return(list(table=overall, total=totals))
}

suppressWarnings(suppressPackageStartupMessages(require(diffHic)))
suppressPackageStartupMessages(require(rhdf5))

dir.create("temp-inter")
dir1<-"temp-inter/1.h5"
dir2<-"temp-inter/2.h5"

comp<-function(npairs1, npairs2, dist, cuts, filter=1L, restrict=NULL, cap=NA) {
	simgen(dir1, npairs1, chromos)
	simgen(dir2, npairs2, chromos)
	param <- pairParam(fragments=cuts, restrict=restrict, cap=cap)
	y<-squareCounts(c(dir1, dir2), param=param, width=dist, filter=filter)

	ar <- anchors(y, type="first")
	tr <- anchors(y, type="second")
	if (nrow(y)) {
		overall<-data.frame(assay(y), paste0(as.character(seqnames(ar)), ":", start(ar), "-", end(ar)),
			paste0(as.character(seqnames(tr)), ":", start(tr), "-", end(tr)), stringsAsFactors=FALSE)
	} else {
		overall <- data.frame(integer(0), integer(0), character(0), character(0), numeric(0),
			stringsAsFactors=FALSE)
	}
	names(overall)<-refnames
	overall<-overall[do.call(order, overall),]
	rownames(overall)<-NULL

	ref<-finder(dir1, dir2, dist=dist, cuts=cuts, filter=filter, restrict=restrict, cap=cap)
	if (!identical(y$totals, ref$total) || 
			!identical(y$totals, totalCounts(c(dir1, dir2), param=param))) {
		stop("mismatches in library sizes") 
	}
	if (!identical(overall, ref$table)) { stop("mismatches in counts or region coordinates") }
	if (filter<=1L && !identical(as.integer(colSums(assay(y))+0.5), y$totals)) { 
		stop("sum of counts from binning should equal totals without filtering") }

	return(head(overall))
}

###################################################################################################
# Checking a vanilla count.

set.seed(1001)
comp(20, 20, dist=10000, cuts=simcuts(chromos))
comp(20, 20, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(20, 20, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(20, 20, dist=10000, cuts=simcuts(chromos), filter=2)
comp(20, 20, dist=10000, cuts=simcuts(chromos), filter=5)
comp(20, 20, dist=5000, cuts=simcuts(chromos))
comp(20, 20, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(20, 20, dist=5000, cuts=simcuts(chromos), filter=2)
comp(20, 20, dist=5000, cuts=simcuts(chromos), filter=5)
comp(20, 20, dist=1000, cuts=simcuts(chromos))
comp(20, 20, dist=1000, cuts=simcuts(chromos), filter=2)
comp(20, 20, dist=1000, cuts=simcuts(chromos), filter=5)

# Repeating a couple of times.
comp(20, 40, dist=10000, cuts=simcuts(chromos))
comp(20, 40, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(20, 40, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(20, 40, dist=10000, cuts=simcuts(chromos), filter=2)
comp(20, 40, dist=10000, cuts=simcuts(chromos), filter=5)
comp(20, 40, dist=5000, cuts=simcuts(chromos))
comp(20, 40, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(20, 40, dist=5000, cuts=simcuts(chromos), filter=2)
comp(20, 40, dist=5000, cuts=simcuts(chromos), filter=5)
comp(20, 40, dist=1000, cuts=simcuts(chromos))
comp(20, 40, dist=1000, cuts=simcuts(chromos), filter=2)
comp(20, 40, dist=1000, cuts=simcuts(chromos), filter=5)

comp(10, 40, dist=10000, cuts=simcuts(chromos))
comp(10, 40, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(10, 40, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(10, 40, dist=10000, cuts=simcuts(chromos), filter=2)
comp(10, 40, dist=10000, cuts=simcuts(chromos), filter=5)
comp(10, 40, dist=5000, cuts=simcuts(chromos))
comp(10, 40, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(10, 40, dist=5000, cuts=simcuts(chromos), filter=2)
comp(10, 40, dist=5000, cuts=simcuts(chromos), filter=5)
comp(10, 40, dist=1000, cuts=simcuts(chromos))
comp(10, 40, dist=1000, cuts=simcuts(chromos), filter=2)
comp(10, 40, dist=1000, cuts=simcuts(chromos), filter=5)

###################################################################################################
# Another example, a bit more extreme with more overlaps.

comp(50, 50, dist=10000, cuts=simcuts(chromos))
comp(50, 50, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(50, 50, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(50, 50, dist=10000, cuts=simcuts(chromos), filter=2)
comp(50, 50, dist=10000, cuts=simcuts(chromos), filter=5)
comp(50, 50, dist=5000, cuts=simcuts(chromos))
comp(50, 50, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(50, 50, dist=5000, cuts=simcuts(chromos), filter=2)
comp(50, 50, dist=5000, cuts=simcuts(chromos), filter=5)
comp(50, 50, dist=1000, cuts=simcuts(chromos))
comp(50, 50, dist=1000, cuts=simcuts(chromos), filter=2)
comp(50, 50, dist=1000, cuts=simcuts(chromos), filter=5)

comp(30, 70, dist=10000, cuts=simcuts(chromos))
comp(30, 70, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(30, 70, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(30, 70, dist=10000, cuts=simcuts(chromos), filter=2)
comp(30, 70, dist=10000, cuts=simcuts(chromos), filter=5)
comp(30, 70, dist=5000, cuts=simcuts(chromos))
comp(30, 70, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(30, 70, dist=5000, cuts=simcuts(chromos), filter=2)
comp(30, 70, dist=5000, cuts=simcuts(chromos), filter=5)
comp(30, 70, dist=1000, cuts=simcuts(chromos))
comp(30, 70, dist=1000, cuts=simcuts(chromos), filter=2)
comp(30, 70, dist=1000, cuts=simcuts(chromos), filter=5)

###################################################################################################
# A final example which is the pinnacle of extremity.

comp(200, 100, dist=10000, cuts=simcuts(chromos))
comp(200, 100, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(200, 100, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(200, 100, dist=10000, cuts=simcuts(chromos), filter=2)
comp(200, 100, dist=10000, cuts=simcuts(chromos), filter=5)
comp(200, 100, dist=5000, cuts=simcuts(chromos))
comp(200, 100, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(200, 100, dist=5000, cuts=simcuts(chromos), filter=2)
comp(200, 100, dist=5000, cuts=simcuts(chromos), filter=5)
comp(200, 100, dist=1000, cuts=simcuts(chromos))
comp(200, 100, dist=1000, cuts=simcuts(chromos), filter=2)
comp(200, 100, dist=1000, cuts=simcuts(chromos), filter=5)

comp(250, 200, dist=10000, cuts=simcuts(chromos))
comp(250, 200, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(250, 200, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(250, 200, dist=10000, cuts=simcuts(chromos), filter=2)
comp(250, 200, dist=10000, cuts=simcuts(chromos), filter=5)
comp(250, 200, dist=5000, cuts=simcuts(chromos))
comp(250, 200, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(250, 200, dist=5000, cuts=simcuts(chromos), filter=2)
comp(250, 200, dist=5000, cuts=simcuts(chromos), filter=5)
comp(250, 200, dist=1000, cuts=simcuts(chromos))
comp(250, 200, dist=1000, cuts=simcuts(chromos), filter=2)
comp(250, 200, dist=1000, cuts=simcuts(chromos), filter=5)

comp(500, 200, dist=10000, cuts=simcuts(chromos))
comp(500, 200, dist=10000, cuts=simcuts(chromos, overlap=4))
comp(500, 200, dist=10000, cuts=simcuts(chromos, overlap=2))
comp(500, 200, dist=10000, cuts=simcuts(chromos), filter=2)
comp(500, 200, dist=10000, cuts=simcuts(chromos), filter=5)
comp(500, 200, dist=5000, cuts=simcuts(chromos))
comp(500, 200, dist=5000, cuts=simcuts(chromos, overlap=2))
comp(500, 200, dist=5000, cuts=simcuts(chromos), filter=2)
comp(500, 200, dist=5000, cuts=simcuts(chromos), filter=5)
comp(500, 200, dist=1000, cuts=simcuts(chromos))
comp(500, 200, dist=1000, cuts=simcuts(chromos), filter=2)
comp(500, 200, dist=1000, cuts=simcuts(chromos), filter=5)

###################################################################################################
# Testing some restriction.

comp(500, 200, dist=10000, cuts=simcuts(chromos), restrict="chrB")
comp(500, 200, dist=10000, cuts=simcuts(chromos, overlap=4), restrict="chrA")
comp(500, 200, dist=10000, cuts=simcuts(chromos, overlap=2), restrict="chrA")
comp(500, 200, dist=10000, cuts=simcuts(chromos), filter=2, restrict="chrB")
comp(500, 200, dist=10000, cuts=simcuts(chromos), filter=5, restrict="chrA")
comp(500, 200, dist=5000, cuts=simcuts(chromos), restrict="chrA")
comp(500, 200, dist=5000, cuts=simcuts(chromos, overlap=2), restrict="chrA")
comp(500, 200, dist=5000, cuts=simcuts(chromos), filter=2, restrict="chrB")
comp(500, 200, dist=5000, cuts=simcuts(chromos), filter=5, restrict="chrA")
comp(500, 200, dist=1000, cuts=simcuts(chromos), restrict="chrA")
comp(500, 200, dist=1000, cuts=simcuts(chromos), filter=2, restrict="chrB")
comp(500, 200, dist=1000, cuts=simcuts(chromos), filter=5, restrict="chrA")

# And the cap.

comp(500, 200, dist=10000, cuts=simcuts(chromos), cap=1)
comp(500, 200, dist=10000, cuts=simcuts(chromos, overlap=4), cap=1)
comp(500, 200, dist=5000, cuts=simcuts(chromos, overlap=2), cap=2)
comp(500, 200, dist=5000, cuts=simcuts(chromos), cap=1)
comp(500, 200, dist=1000, cuts=simcuts(chromos, overlap=4), cap=2)
comp(500, 200, dist=1000, cuts=simcuts(chromos, overlap=2), cap=1)

##################################################################################################
# Cleaning up.

unlink("temp-inter", recursive=TRUE)

##################################################################################################
# End.
