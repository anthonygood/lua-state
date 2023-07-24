local pluck = function (key) return
  function (data) return data[key] end
end

return {
  pluck = pluck
}
