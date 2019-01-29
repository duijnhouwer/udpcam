function selected=uigetioi(y,varargin)
    
    % UIGETIOI - GUI to select intervals of interest from a vector
    %
    %   B=UIGETIOI(Y,...) displays vector Y.
    %
    %   Click button "Select" to select parts of Y using the mouse. Click
    %   "Select" again or press the Enter key to select another interval.
    %
    %   When done selecting, button "OK" closes the window and uigetioi
    %   returns vector B corresponding to Y with values (true/false)
    %   indicating selection.
    %
    %   Additional buttons serve to Undo, Redo, Zoom, Pan, and Cancel.
    %
    %   Cancel is different from OK because it always returns an empty
    %   array, no matter what had been selected.
    %
    %   UIGETIOI accepts these optional parameter-value pairs [default]
    %    name - String displayed in title bar ['uigetioi - Select intervals of interest']
    %    xstr - X-axis label ['Sample number']
    %    ystr - Y-axis label ['Y']
    %    grid - Grid lines ['off'], 'on', 'minor'
    %    axesstyle - Style arguments for axes [{'box','on'}]
    %    linestyle1 - Plot-style of unselected values [{'Color',[0 0 0 1/3],'LineWidth',1.5}]
    %    linestyle2 - Plot-style of selected values [{'Color',[1 0 0 2/3],'LineWidth',1.5}]
    %    position - Window size and position in pixels [left top width height], [[260 500 985 350]];
    %    center - Move window to center of main screen [true], false;
    %    zip - Logical to use mkzip to compress undo/redo history [true if mkzip is present on path (download <a href="https://www.mathworks.com/matlabcentral/fileexchange/69388-mkzip?focused=97b53af9-bfcf-404f-84a0-e758309c34ed&tab=function">here</a>)]
    %
    %   Example
    %    load handel
    %    selected = uigetioi(y,'name','Select Hallelujahs');
    %    selected = bwconncomp(selected)
    %
    %   See also: mkzip, grid, plot, bwconncomp
    
    %   Jacob Duijnhouwer 2018
    
    
    p=inputParser;
    p.addRequired('y');
    p.addParameter('name',[mfilename ' - Select intervals of interest'],@ischar);
    p.addParameter('xstr','Sample number',@ischar);
    p.addParameter('ystr','y',@ischar);
    p.addParameter('grid','off',@(x)any(strcmpi(x,{'on','off','minor'})));
    p.addParameter('axesstyle',{'box','on'});
    p.addParameter('linestyle1',{'Color',[0 0 0 1/3],'LineWidth',1.5},@(x)iscell(x)&&mod(numel(x),2)==0);
    p.addParameter('linestyle2',{'Color',[1 0 0 2/3],'LineWidth',1.5},@(x)iscell(x)&&mod(numel(x),2)==0);
    p.addParameter('position',[260 500 985 350],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
    p.addParameter('center',true,@(x)any(x==[1 0]));
    p.addParameter('zip',exist('mkzip','file'),@islogical);
    p.parse(y,varargin{:});
    p=p.Results;
    
    if p.zip && ~(exist('mkzip','file') || isa(mkzip(1),'mkzip'))
        error('''zip'' is set to true but correct mkzip class function is not on the path (<a href="https://www.mathworks.com/matlabcentral/fileexchange/69388-mkzip?focused=97b53af9-bfcf-404f-84a0-e758309c34ed&tab=function">Download</a> from Matlab File Exchange)');
    end
    
    selected=false(size(y));
    history={}; % for undo/redo
    history_idx=0; % for undo/redo
    hRect=[];
    zoomState=[];
    smpNr=1:numel(y); % sample number
    
    %  Create and then hide the UI as it is being constructed.
    f=figure('Position',p.position,'Visible','off','Units','normalized' ...
        ,'KeyPressFcn',@(src,evnt)onKey(evnt) ...
        ,'CloseRequestFcn',@cancelButton_Callback);
    if p.center
        movegui(f,'center')
    end
    
    % Construct the components.
    selectButton = uicontrol(f,'Style','pushbutton',...
        'String','Select','Units','normalized','Position',[0.9188 0.7714 0.0711 0.0714], ...
        'Callback',@selectButton_Callback);
    undoButton = uicontrol(f,'Style','pushbutton',...
        'String','Undo','Units','normalized','Position',[0.9188 0.6857 0.0711 0.0714], ...
        'Callback',@undoButton_Callback);
    redoButton = uicontrol(f,'Style','pushbutton',...
        'String','Redo','Units','normalized','Position',[0.9188 0.6000 0.0711 0.0714], ...
        'Callback',@redoButton_Callback);
    zoomButton = uicontrol(f,'Style','pushbutton',...
        'String','Zoom','Units','normalized','Position',[0.9188 0.5143 0.0711 0.0714], ...
        'Callback',@zoomButton_Callback);
    panButton = uicontrol(f,'Style','pushbutton',...
        'String','Pan','Units','normalized','Position',[0.9188 0.4286 0.0711 0.0714], ...
        'Callback',@panButton_Callback);
    cancelButton = uicontrol(f,'Style','pushbutton',...
        'String','Cancel','Units','normalized','Position',[0.9188 0.2286 0.0711 0.0714], ...
        'Callback',@cancelButton_Callback);
    okButton = uicontrol(f,'Style','pushbutton',...
        'String','OK','Units','normalized','Position',[0.9188 0.1429 0.0711 0.0714], ...
        'Callback',@okButton_Callback);
    hAx = axes('Units','normalized','Position',[0.0558 0.1429 0.8528 0.8000],p.axesstyle{:});
    align([selectButton,undoButton,redoButton,zoomButton,cancelButton,okButton],'Center','None');
    
    % Initialize the UI.
    f.NumberTitle='Off';
    f.MenuBar='none';
    f.ToolBar='none';
    % Set the title of the figure
    f.Name = p.name;
    % Set the panstate to true (more code below to turn it back on
    % after zooming and area-selection)
    panState=pan(f);
    panState.Enable='On';
    
    % plot the data
    hold(hAx,'on');
    plot(hAx,y,p.linestyle1{:});
    axis(hAx,'tight');
    grid(hAx,p.grid);
    hSelectedDataLine=plot(hAx,nan(size(y)),p.linestyle2{:}); % initially invisible because all are nan
    xlabel(hAx,p.xstr);
    ylabel(hAx,p.ystr);
    
    % store the original limits for unzooming
    fullLimits=axis(hAx);
    
    % Make the window visible.
    f.Visible = 'on';
    
    % Don't return until user closes the window
    uiwait(f);
    
    % Push button callbacks
    function selectButton_Callback(~,~)
        zoomButton.String='Zoom';
        if isempty(hRect)
            % start a new rectangle
            hRect=imrect(hAx);
            rect=wait(hRect); % wait until double clicked on rectangle
            new=true;
        else
            % close the current first, then start a new one
            rect=hRect.getPosition;
            new=false;
        end
        if ~isempty(rect)
            selected(smpNr>=rect(1) & smpNr<=rect(1)+rect(3))=true;
            history_idx=history_idx+1;
            history(history_idx:end)=[]; % once after undo a new one is added, redo is impossible
            if p.zip
                history{history_idx}=mkzip(selected);
            else
                history{history_idx}=selected;
            end
        end
        update_display(hAx);
        if ~new
            selectButton_Callback;
        end
        if isvalid(f)
            uiwait(f);
        end
    end
    
    function undoButton_Callback(~,~)
        delete(hRect);
        hRect=[];
        if history_idx==0
            return;
        end
        history_idx=history_idx-1;
        if history_idx>0
            selected=history{history_idx};
            if p.zip
                selected=selected.unzip;
            end
        else
            selected=false(size(y));
        end
        update_display(hAx);
        if isvalid(f)
            uiwait(f);
        end
    end
    
    function redoButton_Callback(~,~)
        delete(hRect);
        hRect=[];
        if history_idx==numel(history)
            return
        end
        history_idx=history_idx+1;
        selected=history{history_idx};
        if p.zip
            selected=selected.unzip;
        end
        update_display(hAx);
        if isvalid(f)
            uiwait(f);
        end
    end
    
    function zoomButton_Callback(~,~)
        if isvalid(hAx)
            delete(hRect);
            hRect=[];
            if isempty(zoomState) || strcmpi(zoomState.Enable,'off')
                zoomState=zoom(hAx);
                zoomState.Motion='horizontal';
                zoomState.Enable='on';
                zoomButton.String='Unzoom';
            else
                zoomState.Enable='off';
                axis(hAx,fullLimits);
                zoomButton.String='Zoom';
            end
        end
    end
    
    function panButton_Callback(~,~)
        panState.Enable='On';
        zoomButton.String='Zoom';
    end
    
    function cancelButton_Callback(~,~)
        selected=[];
        delete(f); % deletes all children, too
    end
    
    function okButton_Callback(~,~)
        delete(f); % deletes all children, too
    end
    
    function onKey(e) % e for eventdata
        if numel(e.Modifier)==0
            if strcmpi(e.Key,'return')
                selectButton_Callback;
            end
        end
    end
    
    function update_display(hAx)
        if isvalid(hAx)
            delete(hRect);
            hRect=[];
            % updating YData is much faster than plotting from scratch
            hSelectedDataLine.YData(~selected)=nan;
            hSelectedDataLine.YData(selected)=y(selected);
            panState.Enable='On'; % keep allow panning, zoom and selection turn this off
        end
    end
end
