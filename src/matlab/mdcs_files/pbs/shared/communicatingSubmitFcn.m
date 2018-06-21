function communicatingSubmitFcn(cluster, job, environmentProperties)
%COMMUNICATINGSUBMITFCN Submit a communicating MATLAB job to a PBS cluster
%
% Set your cluster's IntegrationScriptsLocation to the parent folder of this
% function to run it when you submit a communicating job.
%
% See also parallel.cluster.generic.communicatingDecodeFcn.

% Copyright 2010-2017 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericPBS:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.communicatingDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericPBS:SubmitFcnError', ...
        'The submit function %s is for use with shared filesystems.', currFilename)
end


if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericPBS:SubmitFcnError', ...
        'The submit function %s only supports clusters with unix OS.', currFilename)
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(environmentProperties.MatlabArguments);
variables = {'MDCE_DECODE_FUNCTION', decodeFunction; ...
    'MDCE_STORAGE_CONSTRUCTOR', environmentProperties.StorageConstructor; ...
    'MDCE_JOB_LOCATION', environmentProperties.JobLocation; ...
    'MDCE_MATLAB_EXE', environmentProperties.MatlabExecutable; ...
    'MDCE_MATLAB_ARGS', matlabArguments; ...
    'MDCE_DEBUG', 'true'; ...
    'MLM_WEB_LICENSE', environmentProperties.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', environmentProperties.UserToken; ...
    'MLM_WEB_ID', environmentProperties.LicenseWebID; ...
    'MDCE_LICENSE_NUMBER', environmentProperties.LicenseNumber; ...
    'MDCE_STORAGE_LOCATION', environmentProperties.StorageLocation; ...
    'MDCE_CMR', cluster.ClusterMatlabRoot; ...
    'MDCE_TOTAL_TASKS', num2str(environmentProperties.NumberOfTasks)};
% Set each environment variable to newValue if currentValue differs.
% We must do this particularly when newValue is an empty value,
% to be sure that we clear out old values from the environment.
for ii = 1:size(variables, 1)
    variableName = variables{ii,1};
    currentValue = cluster.AdditionalProperties.Ppn;
    newValue = variables{ii,2};
    if ~strcmp(currentValue, newValue)
        setenv(variableName, newValue);
    end
end
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);
% Which variables do we need to forward for the job?  Take all
% those that we have set.
variablesToForward = variables(:,1);

% Deduce the correct quote to use based on the OS of the current machine
if ispc
    quote = '"';
else
    quote = '''';
end


% The script name is communicatingJobWrapper.sh
scriptName = 'communicatingJobWrapper.sh';
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
quotedScriptName = sprintf('%s%s%s', quote, fullfile(dirpart, scriptName), quote);

% Choose a file for the output. Please note that currently, JobStorageLocation refers
% to a directory on disk, but this may change in the future.
logFile = cluster.getLogLocation(job);
quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);

jobName = sprintf('Job%d', job.ID);
% PBS jobs names must not exceed 15 characters
maxJobNameLength = 15;
if length(jobName) > maxJobNameLength
    jobName = jobName(1:maxJobNameLength);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Choose a number of processors per node to use
% You may wish to customize this section to match your cluster, 
% for example if you wish to limit the number of nodes that 
% can be used for a single job.
procsPerNode = cluster.AdditionalProperties.Ppn;
numberOfNodes = ceil(environmentProperties.NumberOfTasks/procsPerNode);
additionalSubmitArgs = sprintf('-l nodes=%d:ppn=%d,walltime=%s -q %s -A %s',...
       numberOfNodes, procsPerNode,cluster.AdditionalProperties.Time,...
       cluster.AdditionalProperties.Queue,cluster.AdditionalProperties.Aname);
dctSchedulerMessage(4, '%s: Requesting %d nodes with %d processors per node', currFilename, ...
    numberOfNodes, procsPerNode);
commonSubmitArgs = getCommonSubmitArgs(cluster);
if ~isempty(commonSubmitArgs) && ischar(commonSubmitArgs)
    additionalSubmitArgs = strtrim([additionalSubmitArgs, ' ', commonSubmitArgs]);
end
dctSchedulerMessage(5, '%s: Generating command for task %i', currFilename, ii);
commandToRun = getSubmitString(jobName, quotedLogFile, quotedScriptName, ...
    variablesToForward, additionalSubmitArgs);   

% Now ask the cluster to run the submission command
dctSchedulerMessage(4, '%s: Submitting job using command:\n\t%s', currFilename, commandToRun);
try
    % Make the shelled out call to run the command.
    [cmdFailed, cmdOut] = system(commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
disp(cmdOut);
if cmdFailed
    error('parallelexamples:GenericPBS:SubmissionFailed', ...
        'Submit failed with the following message:\n%s', cmdOut);
end

dctSchedulerMessage(1, '%s: Job output will be written to: %s\nSubmission output: %s\n', currFilename, logFile, cmdOut);

jobIDs = extractJobId(cmdOut);
% jobIDs must be a cell array
if isempty(jobIDs)
    warning('parallelexamples:GenericPBS:FailedToParseSubmissionOutput', ...
        'Failed to parse the job identifier from the submission output: "%s"', ...
        cmdOut);
end
if ~iscell(jobIDs)
    jobIDs = {jobIDs};
end

% set the job ID on the job cluster data
cluster.setJobClusterData(job, struct('ClusterJobIDs', {jobIDs}));
