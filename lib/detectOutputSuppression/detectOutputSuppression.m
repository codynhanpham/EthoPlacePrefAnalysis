function [isTilde, callerTxt, caller, components] = detectOutputSuppression(nout)
% DETECTOUTPUTSUPPRESSION identifies which function outputs have been suppressed
% by the caller using the tilde operator.
%
%   ISTILDE = detectOutputSuppression(nargout)
%   Inside the body of a user-defined function, DETECTOUTPUTSUPPRESSION returns a
%   logical row vector identifying the outputs that were suppressed by the caller.
%   The row vector will be the same length as the number of requested outputs or
%   empty when no outputs were requested explicitly or implicitly. Use MATLAB's
%   <a href="https://www.mathworks.com/help/matlab/ref/nargout.html">nargout</a> function directly as input.
%
%   The function that calls DETECTOUTPUTSUPPRESSION is the inquiry function and
%   is inquiring about the outputs requested by the caller.  DETECTOUTPUTSUPPRESSION
%   reads the entire line that invoked the inquiry function and parses its
%   requested outputs by matching the flexible pattern: "[a,...,z]=fun(" where
%   "fun" is the inquiry function name and must be matched in the caller line.
%
%   [ISTILDE,CALLERTXT] = DETECTOUTPUTSUPPRESSION(nargout) returns a character
%   vector of the entire line that invoked the inquire function.
%
%   [ISTILDE,CALLERTXT,CALLER] = DETECTOUTPUTSUPPRESSION(nargout) returns the
%   call stack structure containing information about the caller, identifying
%   the file, function name, and function line number. If the caller is the
%   command window, CALLER.name will either be 'Command Window' or 'unknown source'.
%
%   [ISTILDE,CALLERTXT,CALLER,COMPONENTS] = DETECTOUTPUTSUPPRESSION(nargout)
%   returns a structure with the fields:
%       rawOut -- a character vector containing the outputs identified by the parser.
%       reducedOutput -- a clean version of rawOut where extra spaces and indexing is
%                        removed.
%       outNames -- 1xn cell array of n character vectors listing the output variable
%                   names or tildes defined in the caller.
%   These fields will be empty if the parser did not detect outputs in square brackets.
%
%	EXAMPLE:
%   See detectOutputSuppression_tester.m for many more examples.
%
%     function main()
%     [mst(1), ~, ~, data] = myFunc();
%
%     function [a, b, c, d] = myFunc()
%     a = 1;  b = 2;  c = 3;  d = 4;
%     [ISTILDE,CALLERTXT,CALLER,COMPONENTS] = detectOutputSuppression(nargout)
%
%     Results:
%         ISTILDE =
%           1×4 logical array
%            0   1   1   0
%
%         CALLERTXT =
%            '[mst(1), ~, ~, data] = myFunc();'
%
%         CALLER =
%           struct with fields:
%             file: 'C:\Users\name\Documents\Matlab\main.m'
%             name: 'main'
%             line: 2
%
%       COMPONENTS
%                rawOut: 'mst(1), ~, ~, data'
%         reducedOutput: 'mst, ~, ~, data'
%              outNames: {'mst'  '~'  '~'  'data'}
%
%   REQUIREMENTS:
%   Internal errors will check for these requirements.
%     1. Multiple outputs must be separated by commas: [a,~,c]=fun();
%     2. DETECTOUTPUTSUPPRESSION must be called from within a MATLAB function.
%     3. The function calling DETECTOUTPUTSUPPRESSION must be invoked from within
%         an m-file or as the most recent command from the command window.
%     4. When in debug mode, only the line currently paused or executed by MATLAB
%         can invoke a function that calls DETECTOUTPUTSUPPRESSION.
%     5. Output assignment to <a href="https://www.mathworks.com/help/matlab/matlab_prog/comma-separated-lists.html">comma-separated lists</a> is not supported.
%     6. The command line that invokes the function containing DETECTOUTPUTSUPPRESSION
%         cannot be split into multiple lines prior to setting the inputs to that
%         function and cannot contain the function name more than once on that line
%         unless preceded by the escape character (e.g. [a,~]=fun(); % /fun()).
%     7. Use MATLAB's <a href="matlab: help('nargout');commandwindow">nargout</a> function directly as the first input to DETECTOUTPUTSUPPRESSION.
%
%   Tested in r2014a,16a,16b,17b,19b,and 2020a.
% Source: <a href = "https://www.mathworks.com/matlabcentral/fileexchange/79218-detectoutputsuppression">detectOutputSuppression</a>
% Author: <a href = "https://www.mathworks.com/matlabcentral/profile/authors/3753776-adam-danz">Adam Danz</a>
% Copyright (c) 2020  All rights reserved
% Revisions
% vs 1.0.0  200817  Uploaded to file exchange
% vs 1.0.1  200817  Added Source link in documentation.
% vs 1.2.0  200817  Outputs must be separated by commas.
% vs 2.0.0  200915  Rigorous detection of parsing errors and 
%   unsupported syntaxes; added components output. Created
%   detectOutputSuppression_tester.m; increased flexibility.
%   Added nargout requirement. 
%% Check input
% 1 and only 1 input required; must be numeric scalar integer larger than 0. Users are strongly
% urged to use the nargout function directly as the input to detectOutputSuppression(nargout).
narginchk(1,1)
validateattributes(nout, {'numeric'}, {'scalar','integer','>=',0},mfilename,'nargout',1)
%% Get caller info
% stack(1) is this function.
% stack(2) is the callee or inquiry-function; it wants to know which of its outputs were suppressed.
% stack(3) is the caller-function that called the callee/inquiry-function. If the caller is the
%   command window, stack(3) doesn't exist.
stack = dbstack('-completenames');
% Define the caller target.
targetCallerLevel = 3;
%% Search the caller line for the output syntax
if ~isempty(stack) && numel(stack)>=targetCallerLevel
    % Confirm that the caller file is supported (currently only m-files).
    caller = stack(targetCallerLevel);
    [~,~,ext] = fileparts(caller.file);
    assert(strcmpi(ext,'.m'),'DETECTOUTSUP:funcSource', ['%s.m only supports '...
        'caller functions invoked by .m files and is not supported when the '...
        'caller function is invoked by the editor''s "Run Section" feature.'],mfilename)
    checkForDebugMode(caller) % First debug check for neg line number.
    % Loop through each line of caller-file until you get to caller line.
    fid = fopen(caller.file);
    for i = 1:caller.line
        callerTxt = fgetl(fid);
    end
    fclose(fid);
    checkForDebugMode(caller,callerTxt,targetCallerLevel); %Check for execution in debug mode
    expectedFcnName = stack(targetCallerLevel-1).name;
    [isTilde, ~, components, inqFcnDetected] = searchForOutputs(callerTxt, expectedFcnName);
    
elseif ~isempty(stack) && numel(stack)==targetCallerLevel-1
    % This suggests that either the inquiry-function was called directly from the
    % command window or from the editor outside of debug mode (ie, highlight + F9).
    % Search the last line of the command history for the inquiry function (undocumented).
    historypath = com.mathworks.mlservices.MLCommandHistoryServices.getSessionHistory;
    callerTxt = char(historypath(end));
    % Locate the caller function invoked within the command window
    expectedFcnName = stack(2).name;
    [isTilde, ~, components, inqFcnDetected] = searchForOutputs(callerTxt,expectedFcnName);
    % If isTilde is not empty, that's pretty good evidence that the most recent command
    % in the command history is the caller.  If isTilde is empty, it could be that the
    % most recent command is the caller but didn't have outputs or it could mean that
    % the most recent command had nothing to do with this in which case we can't identify
    % what the caller is.
    if ~isempty(isTilde)
        caller.name = 'The command window';
    else
        caller.name = 'unknown source';
    end
    caller.line = NaN;
    
elseif ~isempty(stack) && numel(stack)==1
    % This suggests that detectOutputSuppression() was called directly from editor or
    % command window which results in an error (just like nargout() does).
    error('DETECTOUTSUP:badSource', 'You can only call %s from within a MATLAB function.', mfilename)
    
else
    % Who knows what happened here.  This is unexpected.
    error('DETECTOUTSUP:unkn',['Unexpected error. Check that you haven''t shadowed the dbstack function ',...
        'and are fulfilling all requirements.\n%s'],listFuncHints())
end
%% Detect potentially problematic syntaxes
% Test for output parsing errors that may have prevented searchForOutputs() from matching the regexp pattern.
if isempty(components.rawOut) && nout~=0
    % Look into why the regexp pattern was not matched.
    if ~inqFcnDetected
        % Inquiry function name was not detected on the expected line within the caller function. This can
        % happen when the inquiry function is wrapped in an anonymous fcn.
        error('DETECTOUTSUP:noinqfcn',['The expected inquiry function name "%s" was not detected in %s line %d. ',...
            'This could be caused by wrapping the inquiry function within an anonymous function or by calling '...
            'multiple lines from the command window.\n    Evaluated line: %s'],...
            expectedFcnName,caller.name,caller.line,callerTxt)
        
    elseif nout==1
        % The inquiry function was matched but the output may not have been in square brackets which means
        % that there was only 1 output and it was not a tilde. Example: a=myfun();
        isTilde = false;
        
    else
        % The inquiry function name was matched but there was still a parsing error likely with the outputs & >1 expected output.
        error('DETECTOUTSUP:parser',['Outputs could not be parsed from "%s" line %d. The ''nout'' input indicated ',...
            'that there are %d expected outputs but none were detected. Check that this line is meeting all requirements.\n%s\n    ',...
            'Evaluated line: %s'], caller.name, caller.line, nout, listFuncHints(), callerTxt)
        
    end
else
    % Outputs were parsed; check outputs for discrepancies.
    if any(regexp(components.rawOut, '{|\.')) && nout ~= numel(components.outNames)
        % Comma separated list expansion not supported: www.mathworks.com/help/matlab/matlab_prog/comma-separated-lists.html
        % Ex: A=cell(1,3); [A{:}]=fun()   |   S=struct('x',{1,2,3}); [S.x]=fun()
        % In these cases nargout reports the correct number of outputs but may not correspond to the number of vars that were
        % detected by the parser.
        error('DETECTOUTSUP:listExp','Non-scalar cell or structure array indexing is not supported.\n    Evaluated line: %s', callerTxt)
    end
    
    if nout ~= numel(components.outNames)
        % The expected number of outputs specified in nout does not match the number of detected outputs
        error('DETECTOUTSUP:noutChk', ['%s detected %d output(s) but the ''nout'' input indicated %d expected output(s). ',...
            'Check that you are meeting all of the requirements.\n%s\n    Evaluated line: %s'], ...
            mfilename,numel(components.outNames),nout,listFuncHints(),mfilename,callerTxt)
    end
    
end
%% Helper functions
% * searchForOutputs() parses the line of text from the caller fcn to isolate output vars and detect tildes.
% * bracketIdx() determines the nesting structure of brackets that may appear in the output variables.
% * checkForDebugMode() Confirms that the line of code that invoked this file is the "active" line of code (in dubug mode).
% * listFuncHints() outputs a string that can be included in error msgs listing requirements.
function [isTilde, outputs, components, inqFcnDetected] = searchForOutputs(callerTxt,expectedFcnName)
% Parses the entire caller line (callerTxt) to isolate the outputs, matching the inquiry function name (expectedFcnName).
%   isTilde: logical row vec same length as detected number of ouputs; true = tilde suppression.
%   outputs: The string matched by the regexp looking or output pattern and inquiry function name.
%   components: struct containing details about outputs.
%     .rawOut: char; original match by the regexp looking for output pattern and inquiry func name before cleanup.
%     .reducedOutput: char; same as 'outputs'; cleaned up vs of .rawOut.
%     .outNames: cellstr; isolated and cleaned up output names.
%   inqFcnDetected: logical scalar; true = the expected inquiry function name was detected in 'outputs'.
% If isTilde is empty, that means no match. No match could mean no outputs, outputs not in brackets, wrong function
% name, or wrong syntax. That's dealt with later.
% Check that inquiry function isn't called more than once on the same line (\ = escape; e.g. a=fun() %a=\fun())
% "(?<!\\)\b%s\b" (PHP flavor); uses neg lookbehind to match expectedFcnName not preceded by escape char.
callerPattern = sprintf('(?<!\\\\)\\<%s\\>', expectedFcnName);
assert(numel(regexp(callerTxt, callerPattern))<2, 'DETECTOUTSUP:multicall', ...
    ['Inquiry function called more than once on the same line. To avoid this error when caused by a comment, ',...
    'place an escape character just before the function name.  Example: %% y=\\%s(__)\n    Evaluated line: %s'], ...
    expectedFcnName,callerTxt)
% Search for square brackets to the left of the equal sign;
% * Matchs  "[*]=expectedFcnName("  --with optional "(" and optional spaces.
% * Returns only the inside of the outter most sqr brackets.
% "\[(.*)\] *= *\b%s\b( *\()?"  (PHP flavor)
pattern = sprintf('\\[(.*)\\] *= *\\<%s\\>( *\\()?', expectedFcnName);
outputs = regexp(strtrim(callerTxt),pattern,'tokens','once');
% Find tilde locations, if any; Outputs require comma separation when using tildes.
if isempty(outputs)
    isTilde = logical([]);
    outputs = {''};
    components = struct('rawOut', {''}, 'reducedOutput', {''}, 'outNames', {{}});
    inqFcnDetected = numel(regexp(strtrim(callerTxt),sprintf('\\<%s\\>',strtrim(expectedFcnName)),'once'))==1;
else
    inqFcnDetected = true;
    % Detect & adjust for interfering brackets; example: [1:5], [a,b]=myFun()
    [~, bracketLevel] = bracketIdx(['[',outputs{1},']'],'[]');
    outerIdx = find(bracketLevel==0); % 0s mark outer-most "]" and all chars outside of nested [].
    if numel(outerIdx)>1
        % Since the regexp terminates at the function call, the last set of brackets must be the ones containing
        % the outputs. "bracketLevel" shows the nest level of each character in "outputs" for nested brackets.
        % A value of 0 means the character is either outside of all brackets or is the final closing bracket.
        % There should never be negative values which would suggest an incomplete nesting which would cause
        % an error before getting here.  'bracketLevel' should therefore always end with 0 whether it marks the
        % final closing bracket or space between the closing bracket and the function name.
        assert(bracketLevel(end)==0, 'DETECTOUTSUP:brackPat', ['The open|close bracket pattern preceding the '...
            'function name had an unexpected pattern.\n    Caller line: %s'], callerTxt) %probably not possible.
        outputs{1} = outputs{1}(outerIdx(end-1)+1:end);
    end
    components.rawOut = outputs{1}; % store original match
    % Remove any open|closed brackets (including nested ones)
    sxStr = {'()','{}'};
    for i = 1:numel(sxStr)
        [~, ~, bookendIdx] = bracketIdx(outputs{1},sxStr{i});
        if ~isempty(bookendIdx)
            tossIdx = arrayfun(@(a,b){a:b},bookendIdx(1,:),bookendIdx(2,:));
            outputs{1}([tossIdx{:}]) = [];
        end
    end
    % Clean up extra spaces, if needed
    outputs = strtrim(regexprep(outputs{1}, ' +',' '));
    outputNames = strsplit(outputs,',');
    outputNames = cellfun(@strtrim,outputNames,'UniformOutput',false);
    tildeMatches = regexp(outputNames, '^~$');
    isTilde = ~cellfun(@isempty,tildeMatches);
    components.reducedOutput = outputs;
    components.outNames = outputNames;
end
function [openCloseIdx, bracketLevel,bookendIdx] = bracketIdx(str,bracpair)
% Search str for open|close brackets in 'bracpair' and returns the nested bracket structure.
%   str: char vec defined by outputs{1} (e.g. '~, b(2), c(3), ~, ~, ~, g(6)')
%   bracpair: 1x2 char vec containing [open,closed] bracket type (e.g. '()' or '{}')
%   bracketIdx: vec equal length to str where 1 marks positions of bracpair(1), -1 marks pos of brackpair(2), 0s all other chars.
%   bracketLevel = vec equal length to str, intergers >=0, showing nest level of each char; e.g.: [(1:2)+((2):3)] => [0 1 1 1 1 0 0 1 2 2 1 1 1 0 0]
%     0s mark chars outside of all nests *and* 0 marks the last closing bracket of the outer nest.
%   bookendIdx: 2xn subscript indices showing [start;stop] of each of the n outer-most brackets.
%     e.g.: str='a( 1 : 2),d(3,(1)) f(2,(1:(2)))'; bookendIdx = [2,12,21; 9,18,31]
strChars = num2cell(str);
openCloseIdx = strcmp(strChars, bracpair(1)) - strcmp(strChars, bracpair(2));
bracketLevel = cumsum(openCloseIdx);
if any(bracketLevel)
    bookendIdx(1,:) = find(diff([0,bracketLevel])==1 & bracketLevel==1);
    bookendIdx(2,:) = find(diff([0,bracketLevel])==-1 & bracketLevel==0);
else
    bookendIdx = [];
end
function checkForDebugMode(caller,callerTxt,targetCallerLevel)
% checkForDebugMode(caller)
%   Checks that caller.line is non-negative which would indicate stepping past the end of a file
%   in debug mode.
% checkForDebugMode(caller,callerTxt,targetCallerLevel)
%   When running code outside of debug mode, if an error is generated the MException stack should
%   match the dbstack. When in debug mode, if the line being evaluated matches the current line in
%   debug mode (white arrow) then the MException stack and dbstack should also match.  However, when
%   in debug mode and the line being evaluated is not the current debugging line (e.g., "Evaluate
%   Selection" (F9)), the MException stack and dbstack will not match and detectOutputSuppression()
%   will evaluate the current line in debug mode thereby returning unexpected results.  This function
%`  merely checks that the invoking fuction is the same as the line that is evaluated.  If not, error.
if nargin == 1
    assert(caller.line > 0, 'DETECTOUTSUP:negCallLn', ['Dbstack caller line (%d in %s) is negative indicating ',...
        'execution in debug mode. Only the line currently paused or executed by MATLAB can be processed ',...
        'by %s.m.'],caller.line, caller.name,mfilename)
else
    % Compare MException stack and the caller identified by dbstack.
    try
        error('DETECTOUTSUP:dbchk','ME_STACK_CHECK'); % Trigger ME
    catch ME
        if ~strcmp(ME.identifier, 'DETECTOUTSUP:dbchk')
            rethrow(ME) % How'd this happen!?
        end
        if numel(ME.stack)<targetCallerLevel+1 || ~isequal(ME.stack(targetCallerLevel+1), caller)
            % The line evaluated is not the same as the invoking line.
            callerStr = sprintf('''%s'', %d', caller.file, caller.line);
            callerDisp = sprintf('%s (line %d)', caller.name, caller.line);
            callerLinks = ['<a href="matlab:opentoline(',callerStr,')">',callerDisp,'</a>'];
            error('DETECTOUTSUP:debugMd', ...
                ['Mismatch between the invoked and evaluated lines of code likely caused by manually evaluating a line ', ...
                'in debug mode that was not the current line. When in debug mode, only the line currently ',...
                'paused or executed by MATLAB can be processed by %s.m\n    Evaluated line: %s\n                  ',...
                '%s\n    Invoking line: unknown.\n'], mfilename, callerLinks, strtrim(callerTxt))
        end
    end
end
function str = listFuncHints()
% Produces string with hotlinks used in several error messages.
helpStr = ['<a href="matlab: help(''',mfilename,''');commandwindow">See requirements.</a>'];
contactStr = ['<a href="https://www.mathworks.com/matlabcentral/profile/authors/3753776-adam-danz">',...
    'Report this to the developer.</a>'];
str = sprintf('    * %s\n    * %s',helpStr,contactStr);
%% More info
% https://www.mathworks.com/help/matlab/matlab_prog/ignore-function-outputs.html
% https://www.mathworks.com/matlabcentral/answers/580671-can-a-function-known-whether-which-specific-output-is-ignored-tilde-operator
