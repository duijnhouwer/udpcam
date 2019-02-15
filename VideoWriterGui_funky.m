 function out=VideoWriterGui_funky(filename,profile,varargin)
    % Load the information about available profiles
   
     import('audiovideo.internal.writer.profile.ProfileFactory');
     prof_info=ProfileFactory.getKnownProfiles;
      
    if ~exist('filename','var') || isempty(filename)
        filename=fullfile(pwd,datestr(now,'YYYYMMDD_hhmmss'));
    elseif ~ischar(filename)
        error('arg #1 (filename) must be empty or a string');
    end
    if ~exist('profile','var') || isempty(profile)
        profile=prof_info(1).Name;
    elseif ~ischar(profile) || ~any(strcmpi(x,{prof_info(:).Name}))
        error('arg #2 (profile) must be empty or one of the following strings:\n %s',sprintf('\t''%s''\n',prof_info(:).Name));
    end
    p=inputParser;
    p.addParameter('position',[260 500 400 120],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
    p.addParameter('center',true,@(x)any(x==[1 0]));
    p.parse(varargin{:});
    
    % Create the main window
    fig_obj(figure);
    clf(fig_obj);
    set(fig_obj,'Color',[0.94 0.94 0.94]);
    %fig_obj.Position=p.Results.position;
    %  fig_obj.Visible='off';
    set(fig_obj,'Units','Pixels');
    set(fig_obj,'CloseRequestFcn',@close_button_callback);
    set(fig_obj,'ResizeFcn',[]);
    set(fig_obj,'NumberTitle','Off');
    set(fig_obj,'MenuBar','none');
    set(fig_obj,'ToolBar','none');
    set(fig_obj,'Name',mfilename);
    
    % Add the static GUI elements
    build_gui(filename,profile);
    % Put at center of screen if requested
    if p.Results.center
        movegui(fig_obj,'center')
    end
    % Make the window visible.
    set(fig_obj,'Visible','on');
    drawnow;
    uiwait(fig_obj);
    out=vid_obj;
 end

 function out=fig_obj(in)
     persistent p
     if nargin==1
         delete(p);
         p=in;
     end
     out=p;
 end
 
 function out=vid_obj(in)
     persistent p
     if nargin==1
         delete(p)
         p=in;
     end
     out=p;
 end
         

function build_gui(filename,profile)
     import('audiovideo.internal.writer.profile.ProfileFactory');
      prof_info=ProfileFactory.getKnownProfiles;
      
    persistent oldfilename oldprofile
    if strcmpi(oldfilename,filename) && strcmpi(oldprofile,profile)
        return
    end
    oldfilename=filename;
    oldprofile=profile;
    
    % all dimension in pixels
    leftcolwid=140;
    rightcolwid=140;
    hei=20;
    vspace=6;
    hspace=10;
    rowhei=hei+vspace;
    bottom=10;
    left=10;
    
    % Clear all uicontrols
    delete(get(fig_obj,'Children'))
    clf(fig_obj);
    
    
    % Add a file search button
    filebut=uicontrol('Parent',fig_obj,'Style','pushbutton','String','File');
    filebut.Tag='filebut';
    filebut.Callback=@filebut_callback;
    if exist('filename','var')
        filebut.TooltipString=filename;
    end
    % Add profile pop up menu
    profpop=uicontrol('Parent',fig_obj,'Style','popup');
    profpop.String={prof_info(:).Name};
    profpop.Tag='profpop';
    if exist('profile','var')
        profpop.Value=find(strcmpi(profile,{prof_info(:).Name}));
    end
    profpop.Callback=@profpop_callback;
    profpop.ButtonDownFcn=@profpop_callback;
    %
    force_proper_file_extension_and_description();
   
    % Make the video object, which, depending on the profile used
    % will have a number of settable properties
    make_vid_obj;
    propnames=fieldnames(settable_properties(vid_obj));
    propvals=struct2cell(settable_properties(vid_obj));
    % add uicontrols for the settable properties
    
    for i=1:numel(propnames)
        % The property name field
        uicontrol('Parent',fig_obj,'Style','text','String',propnames{i});
        % The corresponding value
        if ~isempty(propvals{i})
            valstr=num2str(propvals{i}); % num2str('asd') > 'asd'
        else
            valstr='[]';
        end
        uicontrol('Parent',fig_obj,'Style','edit','String',valstr,'Tag',['value_' propnames{i}]);
    end
    
    % Add Cancel button
    cancelbut=uicontrol('Parent',fig_obj,'Style','pushbutton','String','Cancel');
    cancelbut.Tag='cancelbut';
    cancelbut.Callback=@cancelbut_callback;
    % Add OK button
    okbut=uicontrol('Parent',fig_obj,'Style','pushbutton','String','OK');
    okbut.Tag='okbut';
    okbut.Callback=@okbut_callback;
    
    % set the window width and height to accomodate all uicontrols
    all_ui=findobj(fig_obj,'Type','UIControl');
    fig_handle=fig_obj;
    fig_handle.Position(3)=3*hspace+leftcolwid+rightcolwid;
    oldhei=fig_handle.Position(4);
    fig_handle.Position(4)=ceil(numel(all_ui)/2)*rowhei+2*vspace;
    fig_handle.Position(2)=fig_handle.Position(2)+oldhei-fig_handle.Position(4);
    % Set the position and size of all uicontrols
    for i=1:2:numel(all_ui)
        all_ui(i).Position=[left+leftcolwid+hspace bottom+floor(i/2)*rowhei rightcolwid hei];
        all_ui(i+1).Position=[left bottom+floor(i/2)*rowhei leftcolwid hei];
    end
    % Cosmetically adjust button and popup menu heights
    for i=1:numel(all_ui)
        if strcmpi(all_ui(i).Style,'pushbutton')
            all_ui(i).Position(2)=all_ui(i).Position(2)-hei*0.2;
            all_ui(i).Position(4)=round(hei*1.25);
        elseif strcmpi(all_ui(i).Style,'popupmenu')
            all_ui(i).Position(2)=all_ui(i).Position(2)+hei*0.2;
            all_ui(i).Position(4)=round(hei/1.2);
        end
    end
    drawnow;
end
function okbut_callback(~,~)
    if make_vid_obj
        delete(fig_obj);
    end
end
function ok=make_vid_obj
    ok=true;
    filebut=findobj(fig_obj,'Tag','filebut');
    profpop=findobj(fig_obj,'Tag','profpop');
    try 
        VW=VideoWriter(filebut.TooltipString,profpop.String{profpop.Value});
        fig_obj_children=get(fig_obj,'Children');
        paramcontrols=fig_obj_children(startsWith({fig_obj_children.Tag},'value_'));
        for i=1:numel(paramcontrols)
            paramname=paramcontrols(i).Tag(numel('value_1'):end);
            newval=eval(strtrim(paramcontrols(i).String));
            if ~all(VW.(paramname)==newval)
                % only setting when changed prevents "compression
                % ratio" cant be set when lossless compression is
                % true for Archival profile
                VW.(paramname)=eval(paramcontrols(i).String);
            end
        end
        vid_obj(VW);
    catch me
        uiwait(errordlg(me.message,mfilename,'modal'));
        ok=false;
    end
end
function cancelbut_callback(~,~)
    vid_obj([]);
    fig_obj([]);
end
function close_button_callback(~,~)
    cancelbut_callback;
end

function profpop_callback(~,~)
    persistent previous_profile
    profpop=findobj(fig_obj,'Tag','profpop');
    filebut=findobj(fig_obj,'Tag','filebut');
    force_proper_file_extension_and_description
    if ~strcmpi(previous_profile,profpop.String{profpop.Value})
        previous_profile=profpop.String{profpop.Value};
        build_gui(filebut.TooltipString,profpop.String{profpop.Value});
    end
end
function filebut_callback(~,~)
    global prof_info
    filebut=findobj(fig_obj,'Tag','filebut');
    % Make the filters (movie extensions)
    ext=[prof_info(:).FileExtensions];
    unique_ext=unique(ext);
    filters{1,1}=strtrim(sprintf('*%s; ',unique_ext{:}));
    filters{1,2}=['MATLAB movie formats (' strtrim(sprintf('*%s, ',unique_ext{:})) ')'];
    filters{1,2}(end-1)=[]; % remove final comma
    filters{2,1}='*.*';
    filters{2,2}='All Files (*.*)';
    % Make the default name (with extension matching the selected profile)
    %  [fld,nme]=fileparts(obj.TooltipString);
    %  fname=fullfile(fld,nme);
    %  if get(findobj(obj.Parent,'Tag','profpop'),'Value')>1
    %      fname=[fname ext{get(findobj(obj.Parent,'Tag','profpop'),'Value')}];
    %  end
    [file,folder]=uiputfile(filters,'Save movie as',filebut.TooltipString);
    if isnumeric(file)
        % user pressed cancel
        return;
    end
    filebut.TooltipString=fullfile(folder,file);
end

function force_proper_file_extension_and_description
      % Set the extension of the filename to confirm the profile and also set
    % the tooltipstring of the popup to show a description of the profile
    import('audiovideo.internal.writer.profile.ProfileFactory');
    prof_info=ProfileFactory.getKnownProfiles;
      profpop=findobj(fig_obj,'Tag','profpop');
    profpop.TooltipString=prof_info(profpop.Value).Description;
    if profpop.TooltipString(end)=='.'
        profpop.TooltipString(end)=[];
    end
    % change the extension of the filename to the selected profile
    filebut=findobj(fig_obj,'Tag','filebut');
    [fld,nme]=fileparts(filebut.TooltipString);
    ext=[prof_info(:).FileExtensions];
    fname=fullfile(fld,nme);
    filebut.TooltipString=[fname ext{profpop.Value}];
end

