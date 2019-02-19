function [vid,prof]=VideoWriterGui(varargin)
    % Load the information about available profiles
    
    import('audiovideo.internal.writer.profile.ProfileFactory');
    prof_info=ProfileFactory.getKnownProfiles;
    
    ss=get(groot,'Screensize');
    defpos=[ss(3)/2 ss(4)/2 ss(3)/6 max(24,round(ss(4)/44))]; % not defpos(4) is height PER ROW in pixels
    fontsize=max(8,8*defpos(4)/24);
    
    p=inputParser;
    p.addParameter('filename',fullfile(pwd,datestr(now,'YYYYMMDD_hhmmss')),@ischar);
    p.addParameter('matlab_presets',true,@(x)any(x==[0 1]));
    p.addParameter('presets',[],@(x)isempty(x) || isstruct(x));
    p.addParameter('default_preset',1,@(x)isnumeric(x) && x>0 && round(x)==x);
    p.addParameter('position',defpos,@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
    p.addParameter('title','VideoWriter Settings',@ischar);
    p.addParameter('center',true,@(x)any(x==[1 0]));
    p.addParameter('modal',true,@(x)any(x==[1 0]));
    p.addParameter('fontsize',fontsize,@isnumeric);
    p.parse(varargin{:});
    
    % Clear the persisten value in the handle function in case a previous
    % run terminated before clearing was reached
    handles('clear');
    % Set the deault return value
    handles('set','return_video',[]);
    handles('set','return_profile',[]);
    
    % Store the height per row and fontsize
    handles('set','px_per_row',p.Results.position(4));
    handles('set','fontsize',p.Results.fontsize);
    
    % make the list of available profiles to select
    if ~isempty(p.Results.presets)
        for i=1:numel(p.Results.presets)
            handles('append','profiles',p.Results.presets(i).profile_name);
            handles('append','profile_descriptions',p.Results.presets(i).profile_desc);
            handles('append','extensions',['.' p.Results.presets(i).VideoWriter.FileFormat]);
            handles('append','videowriters',p.Results.presets(i).VideoWriter);
        end
    end
    if p.Results.matlab_presets
        for i=1:numel(prof_info)
            handles('append','profiles',prof_info(i).Name);
            handles('append','profile_descriptions',prof_info(i).Description);
            handles('append','extensions',prof_info(i).FileExtensions{1});
            handles('append','videowriters',VideoWriter('tmp',prof_info(i).Name));
        end
    end
    if ~isfield(handles,'profiles')
        error('No presets. Provide an array of preset-structures or use matlab''s presets (''matlab_presets'',true)');
    end
    
    % Create the main window
    handles('set','fig',figure('Visible','off'));
    fig=handles('get','fig');
    clf(fig);
    set(fig,'Color',[0.94 0.94 0.94]);
    fig.Position=p.Results.position;
    set(fig,'Resize','off');
    set(fig,'Units','Pixels');
    set(fig,'CloseRequestFcn',@close_button_callback);
    set(fig,'ResizeFcn',[]);
    set(fig,'NumberTitle','Off');
    set(fig,'MenuBar','none');
    set(fig,'ToolBar','none');
    set(fig,'Name',p.Results.title);
    if p.Results.modal
        set(fig,'WindowStyle','modal');
    end
    
    % Add the UIControls
    build_gui(p.Results.filename,p.Results.default_preset);
    % Put at center of screen if requested
    if p.Results.center
        movegui(fig,'center')
    end
    % Make the window visible.
    set(fig,'Visible','on');
    drawnow;
    uiwait(fig);
    vid=handles('get','return_video');
    prof=handles('get','return_profile');
    handles('clear');
 end
 
 function out=handles(method,name,value_or_idx,idx)
     % Way to store global-like variables that are global only to this funtion, not the entire workspace 
     persistent p;
     if isempty(p)
         p=struct;
     end
     if nargin==0
         out=p;
         return
     elseif strcmp(method,'get')
         % value_or_idx is an index, idx is verboten
         if nargin==4
             error('can''t specify idx when method is get')
         end
         if exist('value_or_idx','var')
             out=p.(name){value_or_idx};
         else
             out=p.(name);
         end
         if iscell(out) && numel(out)==1
             out=out{1};
         end
     elseif strcmp(method,'set')
         if exist('idx','var')
             p.(name){idx}=value_or_idx;
         else
             p.(name)={};
             p.(name){1}=value_or_idx;
         end
     elseif strcmp(method,'append') % special case of set
         if nargin==4
             error('can''t specify idx when method is append')
         end
         if ~isfield(p,name)
             p.(name){1}=value_or_idx;
         else
             p.(name){end+1}=value_or_idx;
         end
     elseif strcmp(method,'clear')
         p=[]; % to do: check that all used memory is actually freed (store a huge variable to test)
     else
         error('unknown method')
     end
 end
 
function build_gui(filename,profile)
    if isnumeric(profile)
        if profile<1 || profile>numel(handles('get','profiles'))
            warning('requested default profile is out of range, using top of list');
            profile=1;
        end
        profile=handles('get','profiles',profile);
    end
    
    % Clear all uicontrols
    fig=handles('get','fig');
    delete(get(fig,'Children'));
    clf(fig);

    % Add a file search button
    filebut=uicontrol('Parent',fig,'Style','pushbutton','String','Filename');
    filebut.Tag='filebut';
    filebut.Callback=@filebut_callback;
    if exist('filename','var')
        filebut.TooltipString=filename;
    end
    % Add profile pop up menu
    profpop=uicontrol('Parent',fig,'Style','popup');
    profpop.String=handles('get','profiles');
    profpop.Tag='profpop';
    if exist('profile','var')
        profpop.Value=find(strcmpi(profile,profpop.String));
    end
    profpop.Callback=@profpop_callback;
    profpop.ButtonDownFcn=@profpop_callback;
    %
    force_proper_file_extension_and_description();
   
    % Make the video object, which, depending on the profile used
    % will have a number of settable properties
    vw=handles('get','videowriters',profpop.Value);
    propnames=fieldnames(propvals(vw,'set'));
    pv=struct2cell(settable_properties(vw));
    % add uicontrols for the settable properties
    
    for i=1:numel(propnames)
        % The property name field
        uicontrol('Parent',fig,'Style','text','String',propnames{i});
        % The corresponding value
        if ~isempty(pv{i})
            valstr=num2str(pv{i}); % num2str('asd') > 'asd'
        else
            valstr='[]';
        end
        uicontrol('Parent',fig,'Style','edit','String',valstr,'Tag',['value_' propnames{i}]);
    end
    
    % Add Cancel button
    cancelbut=uicontrol('Parent',fig,'Style','pushbutton','String','Cancel');
    cancelbut.Tag='cancelbut';
    cancelbut.Callback=@cancelbut_callback;
    % Add OK button
    okbut=uicontrol('Parent',fig,'Style','pushbutton','String','OK');
    okbut.Tag='okbut';
    okbut.Callback=@okbut_callback;
    
    % set the window width and height to accomodate all uicontrols
    all_ui=findobj(fig,'Type','UIControl');
    now_n_rows=numel(all_ui)/2;
    set(all_ui,'Units','Normalized');
    % Adjust the height of the window to accomodate the number of rows
    set(fig,'Units','Pixels');
    %  - store old height for post rescale alignment of top
    old_fig_hei = fig.InnerPosition(4);
    %  - set the heightt
    fig.InnerPosition(4)=now_n_rows*handles('get','px_per_row');
    %  - shift the figure vertically to keep the top aligned
    fig.Position(2)=fig.InnerPosition(2)+old_fig_hei-fig.InnerPosition(4);
    set(fig,'Units','Normalized');
    % Set the position and size of all uicontrols
    for i=1:2:numel(all_ui)
        hei=1/now_n_rows*0.8;
        ypos=(i-1)/2/now_n_rows + 1/now_n_rows*0.1;
        all_ui(i).Position=[0.5125 ypos 0.475 hei];
        all_ui(i+1).Position=[0.025 ypos 0.475 hei];
    end
    % Set the fontsize
    set(all_ui,'FontSize',handles('get','fontsize'));
    drawnow;
end
function okbut_callback(~,~)
    make_return_value;
    if ~isempty(handles('get','return_video'))
        delete(handles('get','fig'));
    end
end
function make_return_value
    fig=handles('get','fig');
    filebut=findobj(fig,'Tag','filebut');
    profpop=findobj(fig,'Tag','profpop');
    try 
        profname=profpop.String{profpop.Value};
        if any(profname=='(')
            profname=profname(find(profname=='(')+1:find(profname==')')-1);
        end
        VW=VideoWriter(filebut.TooltipString,profname);
        fig_obj_children=get(fig,'Children');
        paramfields=fig_obj_children(startsWith({fig_obj_children.Tag},'value_'));
        for i=1:numel(paramfields)
            paramname=paramfields(i).Tag(numel('value_1'):end);
            newval=eval(strtrim(paramfields(i).String));
            if ~all(VW.(paramname)==newval)
                % only setting when changed prevents "compression
                % ratio" cant be set when lossless compression is
                % true for Archival profile
                try
                    VW.(paramname)=eval(paramfields(i).String);
                catch innerme
                    if strcmp(innerme.identifier,'MATLAB:set:invalidType')
                        % For example LosslessCompression requires true or
                        % false, 0 or 1 are not accepted! fix that now ...
                        if any(eval(paramfields(i).String)==[0 1])
                            VW.(paramname)=eval(paramfields(i).String)~=0;
                        else
                            rethrow(innerme);
                        end
                    else
                        rethrow(innerme)
                    end
                end
            end
        end
        handles('set','return_video',VW);
        handles('set','return_profile',profname);
    catch me
        uiwait(errordlg(me.message,mfilename,'modal'));
        handles('set','return_video',[]);
        handles('set','return_profile',[]);
    end
end
function cancelbut_callback(~,~)
    delete(handles('get','fig'));
end
function close_button_callback(~,~)
    cancelbut_callback;
end

function profpop_callback(~,~)
    persistent previous_profile
    profpop=findobj(handles('get','fig'),'Tag','profpop');
    filebut=findobj(handles('get','fig'),'Tag','filebut');
    force_proper_file_extension_and_description
    if ~strcmpi(previous_profile,profpop.String{profpop.Value})
        previous_profile=profpop.String{profpop.Value};
        build_gui(filebut.TooltipString,profpop.String{profpop.Value});
    end
end
function filebut_callback(~,~)
    filebut=findobj(handles('get','fig'),'Tag','filebut');
    % Make the filters (filename extensions)
    unique_ext=unique(handles('get','extensions'));
    filters{1,1}=strtrim(sprintf('*%s; ',unique_ext{:}));
    filters{1,2}=['MATLAB movie formats (' strtrim(sprintf('*%s, ',unique_ext{:})) ')'];
    filters{1,2}(end-1)=[]; % remove final comma
    filters{2,1}='*.*';
    filters{2,2}='All Files (*.*)';
    [file,folder]=uiputfile(filters,'Save movie as',filebut.TooltipString);
    if isnumeric(file)
        return; % user pressed cancel
    end
    filebut.TooltipString=fullfile(folder,file);
end

function force_proper_file_extension_and_description
    % Set the extension of the filename to confirm the profile and also set
    % the tooltipstring of the popup to show a description of the profile
    profpop=findobj(handles('get','fig'),'Tag','profpop');
    profpop.TooltipString=handles('get','profile_descriptions',profpop.Value);
    if profpop.TooltipString(end)=='.'
        profpop.TooltipString(end)=[];
    end
    % change the extension of the filename to the selected profile
    filebut=findobj(handles('get','fig'),'Tag','filebut');
    [fld,nme]=fileparts(filebut.TooltipString);
    fname=fullfile(fld,nme);
    filebut.TooltipString=[fname handles('get','extensions',profpop.Value)];
end

