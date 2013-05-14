tab_ids = []
chrome.tabs.query {}, (tabs) ->
    tab_ids = tabs.reverse().map (tab) -> tab.id

setTabTop = (tab_id, offset = 0) ->
    i = _.indexOf(tab_ids, tab_id)
    id = 
        if i != -1
            tab_ids.splice(i, 1)[0]
        else
            tab_id
    tab_ids.splice(offset, 0, id)

chrome.tabs.onActivated.addListener (activeInfo) ->
    setTabTop(activeInfo.tabId)

chrome.tabs.onCreated.addListener (tab) ->
    if tab.id not in tab_ids and tab_ids.length > 0
        setTabTop(tab.id, 1)

chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
    getFunction = ->
        obj = window
        for prop in request.fnname.split('.')
            obj = obj[prop]
        return obj
        
    switch request.type
        when 'call'
            fn = getFunction()
            response = fn.apply(this, request.args)
            sendResponse(response)
        when 'callWithCallback'
            fn = getFunction()
            fn.apply(this, request.args.concat(sendResponse))
        when 'getTab'
            sendResponse(sender.tab)
        when 'getTabs'
            chrome.tabs.query {}, (tabs) ->
                valid_ids = []
                obsoleted_ids = []
                tabs_ = []
                ids = (tabs.map (tab) -> tab.id)
                for id in tab_ids
                    i = _.indexOf(ids, id)
                    if i != -1
                        tabs_.push(tabs[i])
                        valid_ids.push(id)
                    else
                        obsoleted_ids.push(id)
                tabs_ = tabs_.concat(tab for tab in tabs when tab.id not in valid_ids)
                tab_ids = _.difference(tab_ids, obsoleted_ids)
                sendResponse(if request.is_recent_order then tabs_ else tabs)
        when 'getSettings'
            storage.getSettings (settings) ->
                sendResponse(settings)
        when 'setSettings'
            storage.setSettings request.settings, (settings) ->
                sendResponse(settings)
    return true


chrome.runtime.onInstalled.addListener (details) ->
    
