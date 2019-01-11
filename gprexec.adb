with Ada.Text_IO; use Ada.Text_IO;

with GPR.Attr;    use GPR.Attr;
with GPR.Names;   use GPR.Names;
with GPR.Opt;     use GPR.Opt;
with GPR.Util;    use GPR.Util;

package body GPRExec is

   Attr_Dependency : constant Attribute_Data (10) :=
     (Name_Length         => 10,
      Name                => "dependency",
      Attr_Kind           => Associative_Array,
      Index_Is_File_Name  => False,
      Opt_Index           => False,
      Var_Kind            => List,
      Default             => Empty_Value);

   Attr_Process : constant Attribute_Data (7) :=
     (Name_Length         => 7,
      Name                => "process",
      Attr_Kind           => Associative_Array,
      Index_Is_File_Name  => False,
      Opt_Index           => False,
      Var_Kind            => List,
      Default             => Empty_Value);

   Attr_Goals : constant Attribute_Data (5) :=
     (Name_Length         => 5,
      Name                => "goals",
      Attr_Kind           => Single,
      Index_Is_File_Name  => False,
      Opt_Index           => False,
      Var_Kind            => List,
      Default             => Empty_Value);

   type Name_Ids is array (Positive range <>) of Name_Id;
   type Name_Ids_Access is access Name_Ids;
   No_Names : constant Name_Ids_Access := null;

   type Goal_Rec;
   type Goal_Access is access Goal_Rec;
   No_Goal : constant Goal_Access := null;
   type Goals is array (Positive range <>) of Goal_Access;
   type Goals_Access is access Goals;
   No_Goals : constant Goals_Access := null;
   type Goal_Rec is record
      Name         : Name_Id         := No_Name;
      Processed    : Boolean         := False;
      Dependencies : Goals_Access    := No_Goals;
      Process      : Name_Id         := No_Name;
      Arguments    : Name_Ids_Access := No_Names;
      Next         : Goal_Access     := No_Goal;
   end record;

   First_Goal : constant Goal_Access := new Goal_Rec;
   Last_Goal  : Goal_Access := First_Goal;

   function Find_Goal (With_Name : Name_Id) return Goal_Access;
   --  Find a goal with a name; create the goal if it does not yet exist.

   procedure Process (The_Goal : Goal_Access);

   ---------------
   -- Find_Goal --
   ---------------

   function Find_Goal (With_Name : Name_Id) return Goal_Access is
      A_Goal : Goal_Access := First_Goal;
   begin
      while A_Goal /= No_Goal and then A_Goal.Name /= With_Name loop
         A_Goal := A_Goal.Next;
      end loop;

      if A_Goal = No_Goal then
         A_Goal := new Goal_Rec;
         A_Goal.Name := With_Name;
         Last_Goal.Next := A_Goal;
         Last_Goal := A_Goal;
      end if;

      return A_Goal;
   end Find_Goal;

   -------------------
   -- Gprexec_Flags --
   -------------------

   function Gprexec_Flags return Processing_Flags is
   begin
      return
        Create_Flags
          (Report_Error               => null,
           When_No_Sources            => Silent,
           Require_Sources_Other_Lang => False,
           Allow_Duplicate_Basenames  => False,
           Compiler_Driver_Mandatory  => False,
           Error_On_Unknown_Language  => False,
           Require_Obj_Dirs           => Silent,
           Allow_Invalid_External     => Warning,
           Missing_Source_Files       => Silent,
           Ignore_Missing_With        => False,
           Check_Configuration_Only   => False);
   end Gprexec_Flags;

   -------------
   -- Process --
   -------------

   procedure Process (The_Goal : Goal_Access) is
   begin
      if not The_Goal.Processed then
         --  Dependencies

         if The_Goal.Dependencies /= No_Goals then
            for D in The_Goal.Dependencies'Range loop
               Process (The_Goal.Dependencies (D));
            end loop;
         end if;

         --  Process

         if The_Goal.Process /= No_Name then
            declare
               Num_Args : Natural := 0;
            begin
               if The_Goal.Arguments /= No_Names then
                  Num_Args := The_Goal.Arguments'Length;
               end if;

               declare
                  Args : Argument_List (1 .. Num_Args);
                  Success : Boolean := False;
                  The_Process : String_Access;

               begin
                  The_Process :=
                    Locate_Exec_On_Path (Get_Name_String (The_Goal.Process));

                  if The_Process = null then
                     Fail_Program
                       (Project_Tree,
                        "could not find process for goal """ &
                         Get_Name_String (The_Goal.Name) & '"');
                  end if;

                  for J in Args'Range loop
                     Args (J) :=
                       new String'(Get_Name_String (The_Goal.Arguments (J)));
                  end loop;

                  if Verbose_Mode then
                     Put_Line
                       ("Processing """ &
                        Get_Name_String (The_Goal.Name) & '"');
                  end if;

                  Spawn (Program_Name => The_Process.all,
                         Args         => Args,
                         Success      => Success);

                  if not Success then
                     Fail_Program
                       (Project_Tree,
                        "processing of """  & Get_Name_String (The_Goal.Name) &
                          """ failed");
                  end if;

                  The_Goal.Processed := True;
               end;
            end;
         end if;
      end if;
   end Process;

   -------------------------------
   -- Process_Package_Execution --
   -------------------------------

   procedure Process_Package_Execution is
      Exec_Package  : constant Package_Id :=
        Value_Of
          (Name_Execution,
           Main_Project.Decl.Packages,
           Project_Tree.Shared);

      Arr_Elem_Id  : Array_Element_Id;
      Arr_Elem     : Array_Element;

      List : String_List_Id;
      Elem : String_Element;

      A_Goal : Goal_Access;
      Goal_2 : Goal_Access;

   begin
      First_Goal.Name := Goal_Id;

      if Exec_Package = No_Package then
         Fail_Program
           (Project_Tree,
            "no package Execution in main project");
      end if;

      Arr_Elem_Id := Value_Of
           (Name       => Name_Dependency,
            In_Arrays  => Project_Tree.Shared.Packages.Table
              (Exec_Package).Decl.Arrays,
            Shared     => Project_Tree.Shared);
      if Arr_Elem_Id = No_Array_Element then
         if Verbose_Mode and then Verbosity_Level >= Medium then
            Put_Line ("no dependencies");
         end if;
      else
         while Arr_Elem_Id /= No_Array_Element loop
            Arr_Elem :=
              Project_Tree.Shared.Array_Elements.Table (Arr_Elem_Id);

            A_Goal := Find_Goal (With_Name => Arr_Elem.Index);

            List := Arr_Elem.Value.Values;
            while List /= Nil_String loop
               Elem := Project_Tree.Shared.String_Elements.Table (List);
               if Elem.Value = A_Goal.Name then
                  Fail_Program
                    (Project_Tree,
                     "goal """ & Get_Name_String (Elem.Value) &
                     """ cannot depend on itself");
               else
                  Goal_2 := Find_Goal (With_Name => Elem.Value);

                  if A_Goal.Dependencies = No_Goals then
                     A_Goal.Dependencies := new Goals'(1 => Goal_2);

                  else
                     A_Goal.Dependencies :=
                       new Goals'(A_Goal.Dependencies.all & Goal_2);
                  end if;
               end if;

               List := Elem.Next;
            end loop;

            if Verbose_Mode and then Verbosity_Level >= Medium then
               Put ("Dependencies of """ &
                    Get_Name_String (A_Goal.Name) & """:");

               declare
                  Deps : constant Goals_Access := A_Goal.Dependencies;
               begin
                  if Deps /= No_Goals then
                     for G in Deps'Range loop
                        Put (" " & Get_Name_String (Deps (G).Name));
                     end loop;

                     New_Line;
                  end if;
               end;
            end if;

            Arr_Elem_Id := Arr_Elem.Next;
         end loop;
      end if;

      Arr_Elem_Id := Value_Of
           (Name       => Name_Process,
            In_Arrays  => Project_Tree.Shared.Packages.Table
              (Exec_Package).Decl.Arrays,
            Shared     => Project_Tree.Shared);
      if Arr_Elem_Id = No_Array_Element then
         if Verbose_Mode and then Verbosity_Level >= Medium then
            Put_Line ("no processes");
         end if;

      else
         while Arr_Elem_Id /= No_Array_Element loop
            Arr_Elem :=
              Project_Tree.Shared.Array_Elements.Table (Arr_Elem_Id);
            A_Goal := Find_Goal (With_Name => Arr_Elem.Index);
            List := Arr_Elem.Value.Values;

            if List = Nil_String then
               if Verbose_Mode and then Verbosity_Level >= Medium then
                  Put_Line ("no process for goal """ &
                            Get_Name_String (A_Goal.Name) & '"');
               end if;
            else
               while List /= Nil_String loop
                  Elem := Project_Tree.Shared.String_Elements.Table (List);

                  if A_Goal.Process = No_Name then
                     A_Goal.Process := Elem.Value;

                  elsif A_Goal.Arguments = No_Names then
                     A_Goal.Arguments := new Name_Ids'(1 => Elem.Value);

                  else
                     A_Goal.Arguments :=
                       new Name_Ids'(A_Goal.Arguments.all & Elem.Value);
                  end if;

                  List := Elem.Next;
               end loop;

               if Verbose_Mode and then Verbosity_Level >= Medium then
                  Put
                    ("Process of """ & Get_Name_String (A_Goal.Name) & """:");
                  Put (" " & Get_Name_String (A_Goal.Process));

                  declare
                     Args : constant Name_Ids_Access := A_Goal.Arguments;
                  begin
                     if Args /= No_Names then
                        for P in Args'Range loop
                           Put (" " & Get_Name_String (Args (P)));
                        end loop;
                     end if;
                  end;

                  New_Line;
               end if;

            end if;

            Arr_Elem_Id := Arr_Elem.Next;
         end loop;
      end if;

      Process (First_Goal);
   end Process_Package_Execution;

   procedure Register_Package_Execution is
   begin
      Register_New_Package
        (Name       => "execution",
         Attributes =>
           (1 => Attr_Dependency, 2 => Attr_Process, 3 => Attr_Goals));
   end Register_Package_Execution;

end GPRExec;
