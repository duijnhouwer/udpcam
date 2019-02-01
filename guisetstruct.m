function [p,pressedOk] = guisetstruct(p,prompt,maxParmsPerDlg)
% function p = guisetstruct(p,prompt)
% Pass a struct; a list edit box will open with the current values of the
% fields in the struct, the user can edit these, then click ok, and the
% function will return the updated struct. 
% Useful in GUIs where a (varying) number of parameters needs to be set.
% INPUT
% p  = A struct with fields that have numeric or char data.
%       Fields in the struct that are not numeric or char, cannot be changed.
%       (The value in the dialog will be 'FIXED')
% prompt = Optional title for dialog box.
% maxParmsPerDlg = maximum number of fields per dialog, too prevent
% becoming taller than the screen.
% OUTPUT
% p = Updated struct.
%
% BK - May 2010;
% Jacob - Nov 2015: Substructures can now be edited + maxParmsPerDlg
if ~exist('prompt','var') || isempty(prompt)
    prompt = 'Parameter Settings';
end
if ~exist('maxParmsPerDlg','var') || isempty(maxParmsPerDlg)
    maxParmsPerDlg = 15;
end


nParms=numel(fieldnames(p));
if nParms>maxParmsPerDlg
    % If there are more parameters than can be shown vertically on the
    % screen, split them up in a number of chunks and present them one
    % after the other... Ugly, I know...
    nrBatches=ceil(nParms/maxParmsPerDlg);
    msg=[{['The structure you are editing has ' num2str(nParms) ' parameters, more than the ' num2str(maxParmsPerDlg) ' allowed per window. The structure will be split and shown in ' num2str(nrBatches) ' consecutive dialogs.'],' ','Press OK in all dialogs if you want to update any of the parameters.','Press Cancel at any moment to discard all changes and stop editing'}];
   % uiwait(msgbox(msg,mfilename,'modal')); 
     uiwait(msgbox(msg,mfilename)); 
    partialps={};
    batchNr=0;
    c = struct2cell(p); f = fieldnames(p);
    for i=1:maxParmsPerDlg:nParms
        batchNr=batchNr+1;
        thisPrompt=[ num2str(batchNr) '/' num2str(nrBatches) ': ' prompt];
        parsIdx=i:min(i+maxParmsPerDlg-1,nParms);
        subStruct=cell2struct(c(parsIdx),f(parsIdx),1);
        [tmpp,pressedOk]=guisetstruct(subStruct,thisPrompt,maxParmsPerDlg);
        if ~pressedOk
            break; % the for loop
        end
        partialps=[partialps(:); struct2cell(tmpp)];
    end
    if pressedOk
        p=cell2struct(partialps(:),fieldnames(p),1);
    else
        % leave p as it was as input, user presssed cancel
    end
    return;
end



parms = fieldnames(p);   
org = struct2cell(p);

current = struct2cell(p);
uneditable = cellfun(@(x)(~(ischar(x)||isnumeric(x)||islogical(x)||isstruct(x)) || size(x,1)>1),current);
substruct = cellfun(@(x)isstruct(x)&&size(x,1)==1,current);

islog  = cellfun(@(x)(islogical(x)),current);
isnum = cellfun(@(x)(isnumeric(x)),current);
current(isnum|islog) = cellfun(@(x)(num2str(x)),current(isnum | islog),'Uniform',false);

[current{uneditable}] = deal('FIXED');
[current{substruct}] = deal('This is a nested structure. Type VIEW in this field and press OK to view and edit it. You will return to this dialog afterwards.');

%options.WindowStyle = 'modal';
options.Resize = 'on';
options.Interpreter = 'none';

nrLines=ones(size(parms));
nrLines(substruct)=4;

[answer] = inputdlg(parms,prompt,nrLines,current,options);

if isempty(answer)
    % Cancel. No Change
    pressedOk = false;
else
    answer(isnum) = cellfun(@(x)(str2num(x)),answer(isnum),'Uniform',false); %#ok<ST2NM>
    answer(islog) = cellfun(@(x)(logical(str2num(x))),answer(islog),'Uniform',false); %#ok<ST2NM>
    [answer{uneditable}] = deal(org{uneditable});
    for i=find(substruct(:)')
        if strcmpi(strtrim(answer{i}),'VIEW')
            % view/edit the nested structure. return to the nesting level after
            answer{i}=guisetstruct(org{i},['Set substruct ''' parms{i} ''' values ...']);
            guisetstruct(cell2struct(answer,parms),prompt);
        else
            answer{i}=org{i};
        end
    end
    p = cell2struct(answer,parms);
    pressedOk = true;    
end
