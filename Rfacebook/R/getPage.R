#' @rdname getPage
#' @export
#'
#' @title 
#' Extract list of posts from a public Facebook page
#'
#' @description
#' \code{getPage} retrieves information from a public Facebook page. Note that
#' information about users that have turned on the "follow" option on their 
#' profile can also be retrieved with this function.
#'
#'
#' @details
#' This function will only return information from public pages, not users
#' with public profiles.
#'
#' The \code{since} and \code{until} parameters are applied to the \code{updated_time}
#' field in the post objects, and not the \code{created_time}. As a result, this function
#' might return old posts that have been updated recently. 
#'
#' \code{comments_count} refers to the total of comments, including nested comments (replies).
#' It might be different from the total number of comments available through the API if
#' some comments have been deleted.
#'
#' @author
#' Pablo Barbera \email{pablo.barbera@@nyu.edu}
#' @seealso \code{\link{getUsers}}, \code{\link{getPost}}, \code{\link{fbOAuth}}
#'
#' @param page A page ID or page name.
#'
#' @param token Either a temporary access token created at
#' \url{https://developers.facebook.com/tools/explorer} or the OAuth token 
#' created with \code{fbOAuth}.
#'
#' @param n Number of posts of page to return. Note that number can be sometimes
#' higher or lower, depending on status of API.
#'
#' @param since A UNIX timestamp or strtotime data value that points to
#' the start of the time range to be searched. For more information on the
#' accepted values, see: \url{http://php.net/manual/en/function.strtotime.php}
#'
#' @param until A UNIX timestamp or strtotime data value that points to
#' the end of the time range to be searched. For more information on the
#' accepted values, see: \url{http://php.net/manual/en/function.strtotime.php}
#'
#' @param feed If \code{TRUE}, the function will also return posts on the page
#' that were made by others (not only the admin of the page).
#'
#' @param reactions If \code{TRUE}, will add variables to the data frame with
#' the total count of reactions: love, haha, wow, sad, angry.
#'
#' @param verbose If \code{TRUE}, will report a number of the posts retrieved.
#'
#' @param api API version. e.g. "v2.8". \code{NULL} is the default.
#' 
#' @examples \dontrun{
#' ## See examples for fbOAuth to know how token was created.
#' ## Getting information about Facebook's Facebook Page
#'  load("fb_oauth")
#'  fb_page <- getPage(page="facebook", token=fb_oauth)
#' ## Getting posts on Humans of New York page, including posts by others users
#' ## (not only owner of page)
#'  page <- getPage(page="humansofnewyork", token=fb_oauth, feed=TRUE)
#' ## Getting posts on Humans of New York page in January 2013
#'  page <- getPage(page="humansofnewyork", token=fb_oauth, n=1000,
#'    since='2013/01/01', until='2013/01/31')
#' }
#'


getPage <- function(page, token, n=25, since=NULL, until=NULL, feed=FALSE, reactions=FALSE, 
	verbose=TRUE, api=NULL){

	url <- paste0('https://graph.facebook.com/', page,
		'/posts?fields=from,message,created_time,type,link,story,comments.summary(true)',
		',likes.summary(true),shares')
	if (feed){
		url <- paste0('https://graph.facebook.com/', page,
		'/feed?fields=from,message,created_time,type,link,story,comments.summary(true)',
		',likes.summary(true),shares')
	}
	if (!is.null(until)){
		url <- paste0(url, '&until=', until)
	}
	if (!is.null(since)){
		url <- paste0(url, '&since=', since)
	}
	if (n<=25){
		url <- paste0(url, "&limit=", n)
	}
	if (n>25){
		url <- paste0(url, "&limit=25")
	}
	# making query
	content <- callAPI(url=url, token=token, api=api)
	l <- length(content$data); if (verbose) cat(l, "posts ")
	
	## retrying 3 times if error was found
	error <- 0
	while (length(content$error_code)>0){
		cat("Error!\n")
		Sys.sleep(0.5)
		error <- error + 1
		content <- callAPI(url=url, token=token)		
		if (error==3){ stop(content$error_msg) }
	}
	if (length(content$data)==0){ 
		message("No public posts were found : ", page)
		return(data.frame())
	}
	df <- pageDataToDF(content$data)

	# sometimes posts older than 'until' are returned, so here
	# I'm making sure the function stops when that happens
	if (!is.null(since)){
		dates <- formatFbDate(df$created_time, 'date')
		mindate <- min(dates)
		sincedate <- as.Date(since)
	}
	if (is.null(since)){
		sincedate <- as.Date('1970/01/01')
		mindate <- as.Date(Sys.time())
	}

	## paging if n>25
	if (n>25){
		df.list <- list(df)
		while (l<n & length(content$data)>0 & 
			!is.null(content$paging$`next`) & sincedate <= mindate){
			# waiting one second before making next API call...
			Sys.sleep(0.5)
			url <- content$paging$`next`
			content <- callAPI(url=url, token=token, api=api)
			l <- l + length(content$data)
			if (length(content$data)>0){ if (verbose) cat(l, "posts ") }

			## retrying 3 times if error was found
			error <- 0
			while (length(content$error_code)>0){
				cat("Error!\n")
				Sys.sleep(0.5)
				error <- error + 1
				content <- callAPI(url=url, token=token, api=api)
				if (error==3){ stop(content$error_msg) }
			}
			new.df <- pageDataToDF(content$data)
			df.list <- c(df.list, list(new.df))

			if (!is.null(since) & nrow(new.df)>0){
				dates <- formatFbDate(new.df$created_time, 'date')
				mindate <- min(dates)
			}
		}
		df <- do.call(rbind, df.list)
	}
	# returning only those requested
	if (nrow(df)>n){
		df <- df[1:n,]
	}

	# deleting posts after specified date
	if (!is.null(since)){
		dates <- formatFbDate(df$created_time, 'date')
		df <- df[dates>=sincedate,]
	}

	# adding reactions data
	if (reactions==TRUE){
		re = getReactions(df$id, token=token, verbose=FALSE, api=api)
		df <- merge(df, re, all.x=TRUE)
		# sorting
		df <- df[order(df$created_time),]
	}

	return(df)
}

