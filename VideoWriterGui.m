classdef VideoWriterGui < handle
    
    properties (GetAccess=public,SetAccess=private)
        vid_obj
    end
    properties (Access=private)
        fig_obj
        prof_info
    end
    methods
        function [O,vid_obj]=VideoWriterGui(filename,profile,varargin)
            % Load the information about available profiles
            import('audiovideo.internal.writer.profile.ProfileFactory');
            O.prof_info=ProfileFactory.getKnownProfiles;
            
            if ~exist('filename','var') || isempty(filename)
                filename=fullfile(pwd,datestr(now,'YYYYMMDD_hhmmss'));
            elseif ~ischar(filename)
                error('arg #1 (filename) must be empty or a string');
            end
            if ~exist('profile','var') || isempty(profile)
                profile=O.prof_info(1).Name;
            elseif ~ischar(profile) || ~any(strcmpi(x,{O.prof_info(:).Name}))
                error('arg #2 (profile) must be empty or one of the following strings:\n %s',sprintf('\t''%s''\n',O.prof_info(:).Name));
            end
            p=inputParser;
            p.addParameter('position',[260 500 400 120],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
            p.addParameter('center',true,@(x)any(x==[1 0]));
            p.parse(varargin{:});
            
            % Create the main window
            O.fig_obj=figure;
            clf(O.fig_obj);
            O.fig_obj.Color=[0.94 0.94 0.94];
            %O.fig_obj.Position=p.Results.position;
          %  O.fig_obj.Visible='off';
            O.fig_obj.Units='Pixels';
            O.fig_obj.CloseRequestFcn=@O.close_button_callback;
            O.fig_obj.ResizeFcn=[];
            O.fig_obj.NumberTitle='Off';
            O.fig_obj.MenuBar='none';
            O.fig_obj.ToolBar='none';
            O.fig_obj.Name = mfilename;
        
            % Add the static GUI elements
            O.build_gui(filename,profile);
            % Put at center of screen if requested
            if p.Results.center
                movegui(O.fig_obj,'center')
            end
            % Make the window visible.
            O.fig_obj.Visible = 'on';
            drawnow;
            uiwait(O.fig_obj);
            vid_obj=O.vid_obj;
            delete(O);
        end
        
        function build_gui(O,filename,profile)
            
            persistent oldfilename oldprofile
            
            oldfilename
            filename
            oldprofile
            profile
            
            if strcmpi(oldfilename,filename) && strcmpi(oldprofile,profile) 
                return
            end
            oldfilename=filename;
            oldprofile=profile;
            
            disp('build_gui');
            
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
            delete(O.fig_obj.Children)
            clf(O.fig_obj);
            
            
            % Add a file search button
            filebut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','File');
            filebut.Tag='filebut';
            filebut.Callback=@O.filebut_callback;
            if exist('filename','var')
                filebut.TooltipString=filename;
            end
            % Add profile pop up menu
            profpop=uicontrol('Parent',O.fig_obj,'Style','popup');
            profpop.String={O.prof_info(:).Name};
            profpop.Tag='profpop';
            if exist('profile','var')
                profpop.Value=find(strcmpi(profile,{O.prof_info(:).Name}));
            end
            profpop.Callback=@O.profpop_callback;
            profpop.TooltipString='';
            profpop.Callback=@O.profpop_callback;
            profpop.ButtonDownFcn=@O.profpop_callback;
            profpop.TooltipString=O.prof_info(profpop.Value).Description;

            
            % vid_obj=VideoWriter(filebut.TooltipString,profpop.String{profpop.Value});
            % Make the video object, which, depending on the profile used
            % will have a number of settable properties
            O.make_vid_obj;
            propnames=fieldnames(settable_properties(O.vid_obj));
            propvals=struct2cell(settable_properties(O.vid_obj));
            % add uicontrols for the settable properties
            
            for i=1:numel(propnames)
                % The property name field
                uicontrol('Parent',O.fig_obj,'Style','text','String',propnames{i});
                % The corresponding value
                if ~isempty(propvals{i})
                    valstr=num2str(propvals{i}); % num2str('asd') > 'asd'
                else
                    valstr='[]';
                end
                uicontrol('Parent',O.fig_obj,'Style','edit','String',valstr,'Tag',['value_' propnames{i}]);
            end
                
            % Add Cancel button
            cancelbut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','Cancel');
            cancelbut.Tag='cancelbut';
            cancelbut.Callback=@O.cancelbut_callback;
            % Add OK button
            okbut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','OK');
            okbut.Tag='okbut';
            okbut.Callback=@O.okbut_callback; 
            
           % set the window width and height to accomodate all uicontrols
           all_ui=findobj(O.fig_obj,'Type','UIControl');
           O.fig_obj.Position(3)=3*hspace+leftcolwid+rightcolwid;
           oldhei=O.fig_obj.Position(4);
           O.fig_obj.Position(4)=ceil(numel(all_ui)/2)*rowhei+2*vspace;
           O.fig_obj.Position(2)=O.fig_obj.Position(2)+oldhei-O.fig_obj.Position(4);
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
        function okbut_callback(O,~,~)
            if O.make_vid_obj
                delete(O.fig_obj);
            end
        end
        function ok=make_vid_obj(O)
            ok=true;
            filebut=findobj(O.fig_obj,'Tag','filebut');
            profpop=findobj(O.fig_obj,'Tag','profpop');
            try
                delete(O.vid_obj);
                O.vid_obj=VideoWriter(filebut.TooltipString,profpop.String{profpop.Value});
                paramcontrols=O.fig_obj.Children(startsWith({O.fig_obj.Children.Tag},'value_'));
                for i=1:numel(paramcontrols)
                    paramname=paramcontrols(i).Tag(numel('value_1'):end);
                    newval=eval(strtrim(paramcontrols(i).String));
                    if ~all(O.vid_obj.(paramname)==newval)
                        % only setting when changed prevents "compression
                        % ratio" cant be set when lossless compression is
                        % true for Archival profile
                        O.vid_obj.(paramname)=eval(paramcontrols(i).String);
                    end
                end
            catch me
                uiwait(errordlg(me.message,mfilename,'modal'));
                ok=false;
            end
        end
        function cancelbut_callback(O,~,~)
            O.vid_obj=[];
            delete(O.fig_obj);
        end
        function close_button_callback(O,~,~)
            O.cancelbut_callback;
        end
        
        function profpop_callback(O,~,~)
            persistent previous_profile
            profpop=findobj(O.fig_obj,'Tag','profpop');
            profpop.TooltipString=O.prof_info(profpop.Value).Description;
            % change the extension of the filename to the selected profile
            filebut=findobj(O.fig_obj,'Tag','filebut');
            [fld,nme]=fileparts(filebut.TooltipString);
            ext=[O.prof_info(:).FileExtensions];
            fname=fullfile(fld,nme);
            filebut.TooltipString=[fname ext{profpop.Value}];
            %
            if ~strcmpi(previous_profile,profpop.String{profpop.Value})
                previous_profile=profpop.String{profpop.Value};
                O.build_gui(filebut.TooltipString,profpop.String{profpop.Value});
            end
            
        end
        function filebut_callback(O,~,~)
            filebut=findobj(O.fig_obj,'Tag','filebut');
            % Make the filters (movie extensions)
            ext=[O.prof_info(:).FileExtensions];
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
    end
end

