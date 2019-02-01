function udpcam(varargin)
    
    p=inputParser;
    p.addParameter('IP','127.0.0.1',@ischar);
    p.addParameter('LocalPort',4010,@(x)mod(x,1)==0 && x>=1024 && x<=49151);
    p.addParameter('RemotePort',4011,@isnumeric);
    p.addParameter('position',[260 500 640 480],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
    p.addParameter('center',true,@(x)any(x==[1 0]));
    p.parse(varargin{:});
    
    % Set up the UDP connection for receiving commands
    udp_settings.enable=true;
    udp_settings.remotehost=p.Results.IP;
    udp_settings.localport=p.Results.LocalPort;
    udp_settings.remoteport=p.Results.RemotePort;
    udp_connection=[];
    udp_connection=setup_udp_connection(udp_connection,udp_settings);
    
    win=figure('Position',p.Results.position,'Visible','off','Units','normalized' ...
       ,'CloseRequestFcn',@closeButton_Callback); %  ,'KeyPressFcn',@(src,evnt)onKey(evnt)
    if p.Results.center
        movegui(win,'center')
    end
    hAx = axes('Units','normalized','Position',[0 0 1 1],'box','on');
    % Initialize the UI.
    win.NumberTitle='Off';
    win.MenuBar='none';
    win.ToolBar='none';
    % Set the title of the figure
    win.Name = [mfilename ' ' p.Results.IP ':' num2str(p.Results.LocalPort)];
    % Make the window visible.
    win.Visible = 'on';
    
    % The camera object
    if ~isempty(webcamlist)
        camera=webcam;
    else
        camera=[];
    end
    
    shutting_down=false;
    
    % Create the main right-click context menu
    mainMenu = uicontextmenu;
    uimenu('Parent',mainMenu,'Label','UDP Settings...','Callback',@edit_udp_connection);
    cameraMenu=uimenu('Parent',mainMenu,'Label','Camera');
    outputMenu=uimenu('Parent',mainMenu,'Label','Output');
    uimenu('Parent',mainMenu,'Label','Play','Checked','on','Callback',@toggle_play);
    % Build the main menu
    buildMainMenu;
    
    % Initialize the display window
    display=image(hAx,zeros(1,1,3)); % 1 pixel RGB image to initialize
    display.UIContextMenu=mainMenu;
    %try
       main_loop;
    %catch
    %end
    clean_up;

    % --- Sub functions ---------------------------------------------------
    function main_loop
        while ~shutting_down && isvalid(win)
             ttt=tic;
            frame=grab_frame;
            display=show_frame(display,frame);
            pause(1/20-toc(ttt))
        end
    end
    
    function clean_up
        % Clean up
        if isvalid(udp_connection)
            fclose(udp_connection);
        end
        delete(udp_connection);
        delete(camera);
        delete(win);
    end
 
    function closeButton_Callback(~,~)
        set(win, 'pointer', 'watch')
        shutting_down=true; % breaks the video loop and makes that uiwait is skipped after coming out of video loop
        pause(0.2); % give plenty time to finish current cycle of the main_loop
      %  clean_up
    end
    
    function buildMainMenu(~,~)
        % 1 - Get current states to restore after rebuilding the menu
        %   - play state
        playState = get_play;
        if playState
            playCheckmark='on';
        else
            playCheckmark='off'; % important that default is off otherwise starts video loop. The name "buildMainMenu" does not suggest that it would
        end
        populate_camera_settings_menu(cameraMenu)

        
    end
    
    function edit_udp_connection(~,action)
        settings_edit=udp_settings;
        if isa(action,'matlab.ui.eventdata.ActionData')
            % we got here by clicking in the GUI
            while true
                [settings_edit,pressedOk]=guisetstruct(settings_edit,'UDP Settings',8);
                if ~pressedOk
                    return; % user changed their mind, no changes will be made
                end
                errstr=check_for_errors(settings_edit);
                if ~isempty(errstr)
                    uiwait(errordlg(strsplit(errstr,'\n'),mfilename,'modal'));
                else
                    break; % the while loop
                end
            end
        elseif ischar(action)
            % we got here through a UPD command, for exampe 'UDP>enable=1'
            settings_edit=parseUdpAssignment(settings_edit,action);
            error(check_for_errors(settings_edit)); % throws no error if argument is empty
        else
            error('action should be ActionData or an assignstr');
        end
        % Don't check for change, make a new connection regardless
        udp_settings=settings_edit;
        udp_connection=setup_udp_connection(udp_connection,udp_settings);
        %
        function errstr=check_for_errors(setstruct)
            errstr='';
            if ~islogical(setstruct.enable) && ~any(setstruct.enable==[1 0])
                errstr=sprintf('%s\n%s',errstr,'enable must be true or false or 1 or 0');
            end
            if ~ischar(setstruct.remotehost)
                errstr=sprintf('%s\n%s',errstr,'remotehost must be a string');
            end
            if ~isnumeric(setstruct.localport)
                errstr=sprintf('%s\n%s',errstr,'port must be a number');
            end
            if ~isnumeric(setstruct.remoteport)
                errstr=sprintf('%s\n%s',errstr,'port must be a number');
            end
        end
    end
    
    function populate_camera_settings_menu(cameraMenu)
        delete(cameraMenu.Children);
        create_camera_selection_menu(cameraMenu);
    end
  
    function create_camera_selection_menu(hObject,~)
        selectMenu=findobj(cameraMenu.Children,'flat','Label','Select');
        if isempty(selectMenu)
            selectMenu=uimenu('Parent',cameraMenu,'Label','Select');
        else
            delete(selectMenu.Children)
        end
        cams=[webcamlist 'None'];
        for i=1:numel(cams)
            uimenu('Parent',selectMenu,'Label',cams{i},'Callback',@camera_select);
        end
        uimenu('Parent',selectMenu,'Label','Refresh List','Callback',@create_camera_selection_menu);
        if ~isempty(camera) && isvalid(camera)
            camera_select(findobj(selectMenu.Children,'flat','Label',camera.Name));
        else
            set(findobj(selectMenu.Children,'flat','Label','None'),'Checked','on')
        end
    end
    
    
    function camera_select(hObject,~)
        cameraStr=hObject.Text;
        set(hObject.Parent.Children,'Checked','off');
        hObject.Checked='on';
        delete(camera);
        if strcmpi(cameraStr,'None')
            populate_camera_settings_menu(cameraMenu);
        else
            % select the camera
            try
                camera=webcam(cameraStr);
            catch me
                disp(me.message);
                return
            end
            % make the resolution menu and checkmark current resolution
            resos=camera.AvailableResolutions;
            [~,idx]=sort(cellfun(@(x)prod(cellfun(@str2double,regexp(x,'x','split'))),resos),'descend'); % order resos by ...
            resos=resos(idx); % ... number of pixels
            delete(findobj(cameraMenu.Children,'flat','Label','Resolution'));
            resMenu=uimenu('Parent',cameraMenu,'Label','Resolution');
            for i=1:numel(resos)
                uimenu('Parent',resMenu,'Label',resos{i},'Callback',@resolution_select);
            end
            set(findobj(resMenu.Children,'flat','Label',camera.Resolution),'Checked','on');
            % Make the color-space selection menu
            create_color_selection_menu(cameraMenu);
        end
    end
    
       function create_color_selection_menu(cameraMenu)
        spaces={'RGB','Grayscale','R','G','B'};
        delete(findobj(cameraMenu.Children,'flat','Label','Color Space'));
        colorMenu=uimenu('Parent',cameraMenu,'Label','Color Space');
        for i=1:numel(spaces)
            uimenu('Parent',colorMenu,'Label',spaces{i},'Callback',@color_select);
        end
        set(findobj(colorMenu.Children,'flat','Label',spaces{1}),'Checked','on')
    end
    

    function resolution_select(hObject,~)
        if ~isempty(camera) && isvalid(camera) 
            camera.Resolution=hObject.Text;
            grab_frame; % to flush possibly lingering frame of previous resolution
            set(hObject.Parent.Children,'Checked','off');
            hObject.Checked='on';
        end
    end
    
    function screen=show_frame(screen,frame)
        if ~get_play
            return;
        end
        if ~all(size(screen.CData)==size(frame))
            screen=image(screen.Parent,frame);
            screen.UIContextMenu=mainMenu;
            set(screen.Parent,'XTick','','YTick','','box','on');
        else
            screen.CData=frame;
        end
    end
    
    function f=grab_frame
        if ~isempty(camera) && isvalid(camera) && ~shutting_down
            try
                f=camera.snapshot;
            catch me
                % camera.snapshot will throw a timeout error if a settings
                % dialog has been open. Catch that error here and set f to
                % some value
                disp(me.message)
                f=repmat(realsqrt(rand(240,320)),1,1,3);
            end
        else
            f=repmat(realsqrt(rand(240,320)),1,1,3);
        end
        switch get_colorspace
            case 'RGB'
                f=f;
            case 'Grayscale'
                f=repmat(rgb2gray(f),1,1,3);
            case 'R'
                f(:,:,[2 3])=0;
            case 'G'
                f(:,:,[1 3])=0;
            case 'B'
                f(:,:,[1 2])=0;
            otherwise
                error('Unknown colorspace: %s',get_colorspace)
        end
    end
    
    function [bool,playmenuitem] = get_play
        if isempty(mainMenu) || ~isvalid(mainMenu)
            bool=false;
            playmenuitem=[];
            return;
        end
        playmenuitem=findobj(mainMenu.Children,'flat','Label','Play');
        bool=~isempty(playmenuitem) && isvalid(playmenuitem) && strcmpi(playmenuitem.Checked,'on');
    end
    function set_play(bool,playmenuitem)
        if isempty(mainMenu) || ~isvalid(mainMenu)
            return;
        end
        if nargin==1
            playmenuitem=findobj(mainMenu.Children,'flat','Label','Play');
            if isempty(playmenuitem)
                return;
            end
        end
        if bool
            playmenuitem.Checked='on';
        else
            playmenuitem.Checked='off';
        end
    end
    function toggle_play(~,~)
        [play,playmenuitem] = get_play;
        set_play(~play,playmenuitem);
    end
    
    function str=get_colorspace
        menu=findobj(cameraMenu.Children,'flat','Label','Color Space');
        if isempty(menu)
            str='RGB';
        else
            check_item=findobj(menu.Children,'flat','Checked','on');
            str=check_item.Text; % e.g. 'Grayscale'
        end
    end
    
    function color_select(hObject,~)
        set(hObject.Parent.Children,'Checked','off');
        hObject.Checked='on';
    end
    
    function connection=setup_udp_connection(connection,settings)
        if ~isempty(connection)
            fclose(connection);
            delete(connection)
            connection=[];
        end
        try
            connection=udp(settings.remotehost,'RemotePort',settings.remoteport,'LocalPort',settings.localport);
            connection.DatagramReceivedFcn = @parse_message;
            fopen(connection);
            fprintf(connection,'%s online',mfilename);
        catch me
            uiwait(errordlg(me.message,mfilename,'modal'));
        end
    end

    function parse_message(udp_object,udp_struct)
        msg=strtrim(fscanf(udp_object));
        commands=cellfun(@strtrim,regexp(msg,'>','split'),'UniformOutput',false); % 'Color Space > RGB' --> {'Color Space'}    {'RGB'}
        currentmenu=mainMenu;
        for i=1:numel(commands)
            labels={currentmenu.Children.Label};
            match=partialMatch(commands{i},labels,'IgnoreCase',true,'FullMatchPrecedence',true);
            if numel(match)~=1
                fprintf(udp_object,sprintf('Error parsing ''%s'': No partial or full match for %s',msg,commands{i}));
                return
            elseif numel(match)>1
                fprintf(udp_object,sprintf('Error parsing ''%s'': %d matches for ''%s''',msg,numel(match),commands{i}));
                return
            end
            currentmenu=findobj(currentmenu.Children,'flat','Label',match{1});
            if ~isempty(currentmenu.MenuSelectedFcn)
                break;
            end
        end
        try
            if numel(commands)==i % there is a remaining commands
                feval(currentmenu.MenuSelectedFcn,currentmenu)
            elseif numel(commands)==i+1
                feval(currentmenu.MenuSelectedFcn,currentmenu,commands{i+1})
            elseif numel(commands)>i+1 % there are more than 1 remaining commands
                fprintf(udp_object,sprintf('Too many commands after %s>',commands{i}));
            end
        catch me
            fprintf(udp_object,me.message);
        end
    end
    
    function setstruct=parseUdpAssignment(setstruct,assignstr)
        % assignment for example 'value=1' 
        assignstr=strtrim(strsplit(assignstr,'='));
        % now assignment for example {'value'} {'1'}
        if numel(assignstr)~=2
            error('invalid assignment string: %s',action);
        end
        match=partialMatch(assignstr{1},fieldnames(setstruct));
        if numel(match)==0
            error('assignment field ''%s'' does not match any setting',assignstr{1});
        elseif numel(match)>1
            error('assignment field ''%s'' matches multiple (%d) settings',assignstr{1},numel(match));
        end
        setstruct.(match{1})=eval(assignstr{2});
    end
end




