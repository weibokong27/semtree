
semtree <- function(model, data=NULL, control=NULL, constraints=NULL,
                    predictors = NULL,  ...) {
  
  # TODO: change this throughout
  dataset <- data
  
  # obtain dots arguments and test for deprecated use of arguments
  arguments <- list(...)
  if ("global.constraints" %in% names(arguments)) {
    stop("Deprecated use of 'global.constraints'. Please use constraints object")
  }
  if ("invariance" %in% names(arguments)) {
    stop("Deprecated use of 'invariance'. Please use constraints object with property 'local.invariance'")
  }
  
  if (is.null(constraints)) {
    constraints <- semtree.constraints()
  }
  
  covariates <- predictors
  
  # backwards-compatibility
  if ( (!is.null(arguments)) & ("covariates" %in% names(arguments)) ) {
    if (is.null(predictors)) {
      #report(paste("Setting arguments to ",paste(arguments$covariates)),1)
      covariates <- arguments$covariates
    } else {
      stop("Cannot have predictors and covariates in SEM Tree model.")
    }
  }
  
  
  
  invariance <- constraints$local.invariance
  global.constraints <- constraints$global.invariance
  
  
  
  # create default control object, if not specified
  if (is.null(control)) {
    control <- semtree.control()
    if (control$verbose)
      ui_message("Default SEMtree settings established since no Controls provided.")
  } else {
    if (checkControl(control)!=TRUE) {stop( "Unknown options in semtree.control object!");}
  }
  
  # check for correct model entry
  if (inherits(model,"MxModel") || inherits(model,"MxRAMModel")) {
    if (control$verbose) { message("Detected OpenMx model.") }
    control$sem.prog = "OpenMx"
    
    #not.npsol <- (mxOption(NULL,"Default optimizer")!="NPSOL")
    #if (not.npsol) {
    #  warning("semtree recommends the use of NPSOL optimizer!")
    #}
    
  } else if (inherits(model,"lavaan")){
    #if (control$verbose) { ui_message("Detected lavaan model.") }
    control$sem.prog = "lavaan"
  } else if ((inherits(model,"ctsemFit")) || (inherits(model,"ctsemInit"))) {
    #if (control$verbose) { ui_message("Detected ctsem model.") }
    control$sem.prog = "ctsem"
  } else {
    ui_stop("Unknown model type selected. Use OpenMx or lavaanified lavaan models!");
  }
  if (is.na(control$mtry)) control$mtry <- 0
  
  
  # some checks
  if (!is.null(constraints$focus.parameters)) {
    
    if (control$sem.prog != "OpenMx") {
      ui_stop("Focus parameters are only supported with OpenMx!")
    }
    
    num.match <- length(constraints$focus.parameters %in% 
                          OpenMx::omxGetParameters(model))
    if (num.match != length(constraints$focus.parameters)) {
      ui_stop("Error! Not all focus parameters are free parameters in the model!")
    }
  }
  
  # add data to model if not already done and sort covariates from model variables
  ###########################################################
  ###               OPENMX USED HERE                      ###
  ###########################################################
  if((control$sem.prog=='OpenMx') || (control$sem.prog=='ctsem')){
    
    if ((control$sem.prog=='ctsem')) mxmodel <- model$mxobj
    else
      mxmodel <- model
    
    if(is.null(dataset)) {
      if (is.null(mxmodel@data)) {
        stop("MxModel has no data associated!")
      }
      dataset <- mxmodel@data@observed
    }
    
    # sanity check
    if (any(!(covariates %in% names(dataset)))) {
      stop(
        paste("Some of the specified predictors are not in the dataset provided: ",
              paste(covariates[ (!(covariates %in% names(dataset)))],sep="",collapse = ",") 
        ))
    }
    
    # specify covariates from model columns
    if (is.null(covariates)) {    
      model.ids <- rep(NA, length(mxmodel@manifestVars))
      # find the ids in dataset
      for (i in 1:length(model.ids)) {
        cmp <- mxmodel@manifestVars[i] == names(dataset)
        if (all(!cmp)) {
          ui_stop("Error. Variable ",mxmodel@manifestVars[i], " missing in data set!")
        }
        model.ids[i] <- which(cmp);
      }
      all.ids <- 1:length(names(dataset))
      cvid <- sets::as.set(all.ids)-sets::as.set(model.ids) 
      if (length(cvid)==0) {
        ui_stop("Error. No predictors contained in dataset!")
      }
      covariate.ids <- simplify2array( as.vector(cvid,mode="integer") )
    }
    # resort columns to organize covariates
    else {
      all.ids <- 1:length(names(dataset))
      covariate.ids <- sapply(covariates, function(cv) { which(cv==names(dataset))} )
      
      modid <- sets::as.set(all.ids)-sets::as.set(covariate.ids) 
      if (length(modid)==0) {
        ui_stop("No covariates contained in dataset!")
      }
      
      model.ids <- simplify2array( as.vector(modid, mode="integer") )
    }
    
    # Prepare objects for fast score calculation (only for linear models)
    if (control$method == "score") {
      control <- c(control,
                   list(scores_info = OpenMx_scores_input(x = model,
                                                          control = control)))
    } 
    
  }
  
  ###########################################################
  ###               lavaan USED HERE                      ###
  ###########################################################
  if(control$sem.prog=='lavaan'){
    if(is.null(dataset)) {
      ui_stop("Must include data for analysis!")
    }
    # specify covariates from model columns
    if (is.null(covariates)) {    
      model.ids <- rep(NA, length(model@Data@ov.names[[1]]))
      for (i in 1:length(model.ids)) {
        model.ids[i] <- which(model@Data@ov.names[[1]][i] == names(dataset));
      }
      all.ids <- 1:length(names(dataset))
      cvid <- sets::as.set(all.ids)-sets::as.set(model.ids) 
      if (length(cvid)==0) {
        ui_stop("No covariates contained in dataset!")
      }
      covariate.ids <- simplify2array( as.vector(cvid,mode="integer") )
    }
    # resort columns to organize covariates
    else {
      all.ids <- 1:length(names(dataset))
      covariate.ids <- sapply(covariates, function(cv) { which(cv==names(dataset))} )
      
      modid <- sets::as.set(all.ids)-sets::as.set(covariate.ids) 
      if (length(modid)==0) {
        ui_stop("No covariates available to split on!")
      }
      
      model.ids <- simplify2array( as.vector(modid,mode="integer") )
    }
    
    #if (control$verbose) {
      #message("MODEL IDS ",paste(model.ids))
    #  message("COV IDS ",paste(covariate.ids))
    #}
    
  }
  
  meta <- list()
  meta$model.ids <- model.ids
  meta$covariate.ids <- covariate.ids
  
  # init unique node counter
  #	assign("global.node.id",1,envir = getSemtreeNamespace())
  # TODO: is there a better way to assign ids?
  setGlobal("global.node.id",1)
  
  #create default constraints if none specified for invariance testing of nested models
  if (is.null(invariance)) {
    invariance <- NULL	
  }
  else { 
    if (control$method != "naive") {
      ui_message("Invariance is only implemented for naive variable selection.")
      return(NULL)
    }
    if(is.na(control$alpha.invariance)){
      ui_message("No Invariance alpha selected. alpha.invariance set to:", control$alpha)
      control$alpha.invariance<-control$alpha}
	  
	  if(is(invariance, "character")) {
		  invariance <- list(invariance)
		  } else {
			  if (!is(invariance, "list")) {
				  ui_stop("Invariance must contain an array of parameter names or a list of such arrays.")
			  }
		  }

  }
  

  
  # correct method selection check
  method.int <-  pmatch(control$method, 	c("cv","naive","fair","fair3","score"))	
  if (is.na(method.int)) {
    ui_stop("Unknown method in control object! Try either 'naive', 'fair', 'fair3', 'score', or 'cv'.")
  }	
  
  # if this is still null, no data was given
  if (is.null(dataset)) {
    ui_stop("No data were provided!")
  }
  
  # sanity checks, duplicated col names?
  if (any(duplicated(names(dataset))))
  {
    ui_stop("Dataset contains duplicated columns names!")
  }
  
  # set a seed for user to repeat results if no seed provided
  if (!is.null(control$seed)&!is.na(control$seed)){
    set.seed(control$seed)
  }
  ###########################################################
  ###               OPENMX USED HERE                      ###
  ###########################################################
  # global constraints - estimate once and then regarded fixed in the tree
  if (!is.null(global.constraints)) {
    
    if (control$sem.prog != "OpenMx") {
      ui_stop("Global constraints are not yet supported!")
    }
    
    run.global <- OpenMx::mxRun(model, silent=T, useOptimizer=T, suppressWarnings=T);
    labels <- names(OpenMx::omxGetParameters(model))
    eqids <- which(labels %in% global.constraints)
    neqids <- which(!labels %in% global.constraints)
    values <- OpenMx::omxGetParameters(run.global)[eqids]
    model <- OpenMx::omxSetParameters(model, 
               labels=global.constraints,free=F, values=values)
    # FIX THIS LINE HERE
    
    # Read Global Constraints and New model Parameters Here.
    ui_message("Global Constraints:\n",paste(global.constraints,collapse=" "))
    ui_message("Freely Estimated Parameters:\n",paste(names(OpenMx::omxGetParameters(model)),collapse=" "))
  }
  
  
  # grow tree
  if(control$sem.prog == 'OpenMx'){
    if (control$verbose){message('OpenMx model estimation selected!')}
  } 
  else if(control$sem.prog == 'lavaan'){
    if (control$verbose){message('lavaan model estimation selected!')}
    
  }
  else if(control$sem.prog == 'ctsem'){
    if (control$verbose){message('ctsem model estimation selected!')}
  }
  else {
    stop("Unknown model type. Use OpenMx or lavaans models only!")
  }
  
  # save time before starting the actual tree growing
  start.time <- proc.time()
  
  # start the recursive growTree() function to do the 
  # actual heavy lifting
  tree <- growTree(model=model, mydata=dataset, control=control, 
                   invariance=invariance, meta=meta, 
                   constraints=constraints, ...)
  
  # determine time elapsed
  elapsed <- proc.time()-start.time
  
  
  # save various information in the result object and
  # assign it class 'semtree'
  tree$elapsed <- elapsed
  tree$control <- control
  tree$constraints <- constraints
  tree$version <- tryCatch(sessionInfo()$otherPkgs$semtree$Version)
  class(tree) <- "semtree"
  
  # tell the user that everything is OK
  ui_ok("Tree construction finished [took ",
        human_readable_time(elapsed[3]),"].")
  
  return(tree)
  
}
