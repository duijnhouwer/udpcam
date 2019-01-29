function udpcam(varargin)
    p=inputParser;
    p.addParameter('RemoteHost','127.0.0.1',@ischar);
    p.addParameter('LocalPort',4010,@(x)mod(x,1)==0 && x>=1024 && x<=49151);
    p.addParameter('RemotePort',4011,@isnumeric);
    p.addParameter('position',[260 500 640 480],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
    p.addParameter('center',true,@(x)any(x==[1 0]));
    p.parse(varargin{:});
    
    % Set up the UDP connection for receiving commands
    udp_settings.enable=true;
    udp_settings.remotehost=p.Results.RemoteHost;
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
    win.Name = [mfilename ' ' p.Results.RemoteHost ':' num2str(p.Results.LocalPort)];
    % Make the window visible.
    win.Visible = 'on';
    
    % The camera object
    if ~isempty(webcamlist)
        camera=webcam;
    else
        camera=[];
    end
    
    shutting_down=false;
    
    % Create the context menu with the camera select callback
    mainMenu = uicontextmenu;
    initMainMenu;
    screen=image(hAx,zeros(1,1,3)); % 1 pixel RGB image to start
    screen.UIContextMenu=mainMenu;
    set(screen.Parent,'XTick','','YTick','','box','on');
    set_play(true);
    while ~shutting_down && isvalid(win)
        ttt=tic;
        frame=grab_frame;
        screen=show_frame(screen,frame);
        pause(1/20-toc(ttt))
    end
    % Clean up
    if isvalid(udp_connection)
        fclose(udp_connection);
    end
    delete(udp_connection);
    delete(win);
    
    % --- Sub functions ---------------------------------------------------
    
    function closeButton_Callback(~,~)
        set(win, 'pointer', 'watch')
        shutting_down=true; % breaks the video loop and makes that uiwait is skipped after coming out of video loop
        pause(0.2); % give plenty time to finish current cycle of the show video loop
        uiresume(win); % breaks uiwait(f) loop if control was there (as opposed to in video loop)
    end
    
    function initMainMenu(~,~)
        % 1 - Get current settings before resetting
        %   - play state
        playState = get_play;
        if playState
            playCheckmark='on';
        else
            playCheckmark='off'; % important that default is off otherwise starts video loop. The name "initMainMenu" does not suggest that it would
        end
        %   - color state
        colorState = get_colorspace;
        % 2 - Remove all items (that's why we first collected settings)
        delete(mainMenu.Children);
        % 3 - Add menu's back in
        %   - Add the UDP configuration menu
        uimenu('Parent',mainMenu,'Label','UDP Settings...','Checked',playCheckmark,'Callback',@edit_udp_connection);
        %   - Add the camera selection menu
        create_camera_selection_menu
        %   - Add the color menu
        create_color_selection_menu(colorState)
        %   - Add the play button
        uimenu('Parent',mainMenu,'Label','Play','Checked',playCheckmark,'Callback',@toggle_play);
    end
    
    function edit_udp_connection(~,~)
        while true
            [settings,pressedOk]=guisetstruct(udp_settings,'UDP Settings',8);
            if ~pressedOk
                return;
            end
            errstr={};
            if ~islogical(settings.enable)
                errstr{end+1}='enable should be 0 or 1';
            end
            if ~ischar(settings.host_ip)
                errstr{end+1}='host_ip should be a string';
            end
            if ~isnumeric(settings.remote_port)
                errstr{end+1}='port must be a number';
            end
            if ~isempty(errstr)
                msg=errstr;
                uiwait(errordlg(msg,mfilename,'modal'));
            else
                break; % the while loop
            end
        end
        % Don't check if anything has changed, make a new connection
        % eitherway (user can press cancel to prevent that)
        udp_connection=setup_udp_connection(udp_connection,udp_settings);
    end
  
    function create_camera_selection_menu(~,~)
        cameraMenu=findobj(mainMenu.Children,'flat','Label','Select Camera');
        if isempty(cameraMenu)
            cameraMenu=uimenu('Parent',mainMenu,'Label','Select Camera');
        else
            delete(cameraMenu.Children)
        end
        cams=[webcamlist 'None'];
        for i=1:numel(cams)
            uimenu('Parent',cameraMenu,'Label',cams{i},'Callback',@camera_select);
        end
        uimenu('Parent',cameraMenu,'Label','Refresh List','Callback',@create_camera_selection_menu);
        if ~isempty(camera) && isvalid(camera)
            camera_select(findobj(cameraMenu.Children,'flat','Label',camera.Name'));
        else
            set(findobj(cameraMenu.Children,'flat','Label','None'),'Checked','on')
        end
    end
    
      function create_color_selection_menu(colorState)
        colorMenu=findobj(mainMenu.Children,'flat','Label','Color Space');
        if isempty(colorMenu)
            colorMenu=uimenu('Parent',mainMenu,'Label','Color Space');
        else
            delete(colorMenu.Children)
        end
        spaces={'RGB','Grayscale','R','G','B'};
        for i=1:numel(spaces)
            uimenu('Parent',colorMenu,'Label',spaces{i},'Callback',@color_select);
        end
        set(findobj(colorMenu.Children,'flat','Label',colorState),'Checked','on')
    end
    
    
    function camera_select(hObject,~)
        cameraStr=hObject.Text;
        set(hObject.Parent.Children,'Checked','off');
        hObject.Checked='on';
        delete(camera);
        if strcmpi(cameraStr,'None')
            initMainMenu
        else
            % select the camera
            camera=webcam(cameraStr);
            % make a resolution menu and checkmark current resolution
            resos=camera.AvailableResolutions;
            [~,idx]=sort(cellfun(@(x)prod(cellfun(@str2double,regexp(x,'x','split'))),resos),'descend'); % order resos by number of pixels
            resos=resos(idx);
            delete(findobj(mainMenu.Children,'flat','Label','Resolution'));
            resMenu=uimenu('Parent',mainMenu,'Label','Resolution');
            for i=1:numel(resos)
                uimenu('Parent',resMenu,'Label',resos{i},'Callback',@resolution_select);
            end
            set(findobj(resMenu.Children,'flat','Label',camera.Resolution),'Checked','on');
        end
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
            f=camera.snapshot;
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
        menu=findobj(mainMenu.Children,'flat','Label','Color Space');
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
            matches=strcmpi(labels,commands{i});
            if ~any(matches) % no full match, try partial matching
                matches=startsWith(labels,commands{i},'IgnoreCase',true);
                if ~any(matches)
                   % fprintf(udp_object,'No matches %s',msg);
                    fprintf(udp_object,sprintf('Error parsing ''%s'': No partial or full match for %s',msg,commands{i}));
                    return
                elseif sum(matches)>1
                    fprintf(udp_object,'Too many mathces');
                    % fprintf(udp_object,'Error parsing ''%s'': %d matches for ''%s''',msg,sum(matches),commands{i});
                    return
                end
            end
            currentmenu=findobj(currentmenu.Children,'flat','Label',labels{matches});
        end
        feval(currentmenu.MenuSelectedFcn,currentmenu)
        disp('done with feval');
    end
end




