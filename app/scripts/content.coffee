# require hapt_mod.js, underscore.js

settings = null

callbg = (cb, fnname, args...) ->
    chrome.runtime.sendMessage {type: 'call', fnname: fnname, args: args}, (response) ->
        cb?(response)

callbgcb = (cb, fnname, args...) ->
    chrome.runtime.sendMessage {type: 'callWithCallback', fnname: fnname, args: args}, (response) ->
        cb?(response)

getTab = (cb) ->
    chrome.runtime.sendMessage {type: 'getTab'}, (tab) ->
        cb?(tab)

getTabs = (cb) ->
    chrome.runtime.sendMessage {type: 'getTabs', is_recent_order: settings.is_recent_order}, (tabs) ->
        cb?(tabs)

haptListen = (cb) ->
    hapt_mod.listen( (keys, type, event) ->
        cb(keys, type, event)
    , window, true, [])

chrome.runtime.sendMessage {type: 'getSettings'}, (_settings) ->
    settings = _settings

    bindings = 
        menu_modifier: settings.menu_modifier
        next_menu_tab: settings.bindings.next_menu_tab
        prev_menu_tab: settings.bindings.prev_menu_tab
       
    hapt_listener = haptListen (keys, type, event) ->
        switch type
            when 'keydown'
                mods = [bindings.menu_modifier]
                direct = _.difference(keys, mods)
                direct =
                    if (bindings.next_menu_tab.some (s) -> _.isEqual(direct, _.difference(s, mods))) then 'next'
                    else if (bindings.prev_menu_tab.some (s) -> _.isEqual(direct, _.difference(s, mods))) then 'prev' else null
                if bindings.menu_modifier in keys and direct?
                    Menu.get().activate(if direct == 'next' then 1 else if direct == 'prev' then -1 else 0)
                    return false
            when 'keyup'
                if keys[0] == bindings.menu_modifier
                    Menu.get().activateTab()
        return true


    mouse_listen = ->
        button_map =
            0: 'Left'
            1: 'Middle'
            2: 'Right'

        return if not settings.menu_rocker_button in _.values(button_map)

        is_pressing = false
            
        mousedown_listener = window.addEventListener('mousedown', (event) ->
            if settings.menu_rocker_button == button_map[event.button]
                is_pressing = true
        , true)
     
        mouseup_listener = window.addEventListener('mouseup', (event) ->
            if settings.menu_rocker_button == button_map[event.button]
                is_pressing = false
                Menu.get().activateTab()
        , true)
     
        mousewheel_listener = window.addEventListener('mousewheel', (event) ->
            if is_pressing
                Menu.get().activate(if event.wheelDeltaY > 0 then -1 else if event.wheelDeltaY < 0 then 1 else 0)
                event.preventDefault()
                event.stopImmediatePropagation()
        , true)

    mouse_listen()

class Menu
    instance = null
    
    # get singleton instance
    @get: ->
        instance ?= new _Menu()
    
    class _Menu
        constructor: ->
            @tabs = null
            @selected = null
            @element = null
            @blur_listener = null
            @mouseover_listener = null

        template: _.template("""
            <ul>
                <% _.each(tabs, function(tab){ %>
                    <li class="<%= tab._selected ? 'selected' : '' %>" data-tab-id="<%= tab.id %>">
                        <img src="<%= tab.favIconUrl %>">
                        <span><%- tab.title %></span>
                    </li>
                <% }); %>
            </ul>
        """)
        
        createElement: (visibility = false) =>
            if not @element?
                @element = document.createElement('div')
                @element.className = 'moly_tab_menu'
                if @tabs?
                    @element.innerHTML = @template(@)
                @element.style.visibility = if visibility then 'visible' else 'hidden'
                document.querySelector('body').appendChild(@element)
                @element.setAttribute('tabindex', -1)
                if not @blur_listener?
                    @blur_listener = =>
                        @hide()
                        return true
                    @element.addEventListener('blur', @blur_listener)
                if not @mouseover_listener?
                    @mouseover_listener = (event) =>
                        li = event.target
                        return if li.nodeName.toLowerCase() != 'li'
                        tab_id = parseInt(li.getAttribute('data-tab-id'))
                        tab_index = _.indexOf (@tabs.map (tab) -> tab.id), tab_id
                        @selectTab(tab_index) if tab_index != -1
                        return true
                    @element.addEventListener('mouseover', @mouseover_listener)

        loadTabs: (cb = null) =>
            getTabs (tabs) =>
                @tabs = tabs
                cb?()

        activate: (direction = 0) =>
            scroll = =>
                ul = @element.querySelector('ul')
                li = ul.querySelectorAll('li')[@selected]
                ul_height = (@element.offsetHeight - ul.offsetTop * 2)
                if li.offsetTop + li.offsetHeight > ul_height + @element.scrollTop
                    @element.scrollTop = li.offsetTop + li.offsetHeight - ul_height
                else if li.offsetTop - @element.scrollTop < 0
                    @element.scrollTop = li.offsetTop
            if not @element?
                @createElement()
                @loadTabs =>
                    getTab (tab) =>
                        @tabs = _.filter @tabs, (t) -> t.windowId == tab.windowId
                        @element.innerHTML = @template(@)
                        @setRect()
                        current_index = _.indexOf (@tabs.map (t) -> t.id), tab.id
                        current_index = if current_index == -1 then 0 else current_index
                        @selectTab(((current_index + direction) % @tabs.length + @tabs.length) % @tabs.length)
                        scroll()
                        @element.style.visibility = 'visible'
                        @element.focus()
            else if @selected?
                @selectTab(((@selected + direction) % @tabs.length + @tabs.length) % @tabs.length)
                scroll()
                    
        activateTab: () =>
            if @tabs? and @selected?
                callbg(null, 'chrome.tabs.update', @tabs[@selected].id, {active: true})
                @hide()
         
        selectTab: (tab_index) =>
            if @selected?
                @tabs[@selected]?._selected = false
                @element.querySelectorAll('li')[@selected].className = ''
            @selected = tab_index
            @tabs[@selected]?._selected = true
            @element.querySelectorAll('li')[@selected].className = 'selected'

        hide: =>
            @selected = null
            @element?.removeEventListener('blur', @blur_listener) if @blur_listener?
            @blur_listener = null
            @element?.removeEventListener('mouseover', @mouseover_listener) if @mouseover_listener?
            @mouseover_listener = null
            document.querySelector('body').removeChild(@element) if @element?
            @element = null

        setRect: =>
            VMARGIN = 0
            client =
                width: window.innerWidth or document.documentElement.clientWidth
                height: window.innerHeight or document.documentElement.clientHeight
            @element.style.height = "#{_.min([@element.offsetHeight, client.height - VMARGIN * 2])}px"
            @element.style.left = "#{(client.width - @element.offsetWidth) / 2}px"
            @element.style.top = "#{(client.height - parseInt(@element.style.height)) / 2}px"
