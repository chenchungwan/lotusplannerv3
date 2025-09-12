//
//  GlobalNavBar.swift
//  LotusPlannerV3
//
//  Created by Christine Chen on 9/11/25.
//

import SwiftUI

struct GlobalNavBar: View {
    var body: some View {
        VStack {
            HStack {
                Menu {
                    Button("Settings", action: { print("Option 1 selected") })
                    Button("About", action: { print("Option 2 selected") })
                    Button("Feedback", action: { print("Option 3 selected") })
                } label: {
                    Image(systemName: "sidebar.left")
                }
             
                
                Button {
                print("go back a day")
                } label: {
                    Image(systemName: "chevron.backward")
                }

                
                Text("Date/Date Range Label")
                
                Button {print("go forward a day")} label: {
                    Image(systemName: "chevron.forward")}
                
                
                Spacer()
                
                
                Button {print("go forward a day")} label: {
                    Image(systemName: "eye.circle")}
                Button {print("go forward a day")} label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")}
        
                
                Menu("Add") {
                    Text("Event")
                    Text("Task")
                }
//                Image(systemName: "plus")
            }
            HStack {
                Button {print("go forward a day")} label: {
                    Image(systemName: "d.circle")}
        
                Button {print("go forward a day")} label: {
                    Image(systemName: "w.circle")}
        
        
                Button {print("go forward a day")} label: {
                    Image(systemName: "m.circle")}
        
                Button {print("go forward a day")} label: {
                    Image(systemName: "y.circle")}
        
                Button {print("go forward a day")} label: {
                    Image(systemName: "a.circle")}
        
                
    
               
               
              
            
                
                Menu {
                    Button("Has Due Date", action: { print("Option 1 selected") })
                    Button("No Due Date", action: { print("Option 2 selected") })
                    Button("Overdue", action: { print("Option 3 selected") })
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                
              
            }
        }
    }
}

    
    #Preview {
        GlobalNavBar()
    }
